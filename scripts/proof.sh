#!/usr/bin/env bash
# Runs the "Before committing" checks from .claude/CLAUDE.md against what
# changed. Shared by the git commit gate (.githooks/pre-commit), CI, the
# /proof command, and humans. Never contacts the Proxmox node or a guest.
#
#   scripts/proof.sh [--staged]   files in the git index (default)
#   scripts/proof.sh --all        every tracked file

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

# Hooks don't run under direnv, so .envrc's export may be missing.
export ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-$PWD/ansible/ansible.cfg}"

TF_DIR=terraform/environments/homelab

mode=staged
case "${1:---staged}" in
  --staged) ;;
  --all) mode=all ;;
  *) echo "usage: scripts/proof.sh [--staged|--all]" >&2; exit 64 ;;
esac

if [ "$mode" = all ]; then
  mapfile -t files < <(git ls-files)
else
  mapfile -t files < <(git diff --cached --name-only --diff-filter=ACMR)
fi

tf_changed=0
tfstate=()
ansible_yml=()
playbooks=()
workflows=()
collection_reqs=()
deploy_targets=0
plan_protected=0
for f in "${files[@]}"; do
  case "$f" in
    *.tfstate|*.tfstate.*) tfstate+=("$f") ;;
  esac
  case "$f" in
    scripts/deploy-targets.sh|scripts/tests/deploy-targets.sh) deploy_targets=1 ;;
    scripts/checks/plan-protected.sh|scripts/tests/plan-protected.sh) plan_protected=1 ;;
  esac
  case "$f" in
    terraform/*) tf_changed=1 ;;
    .github/workflows/*.yml|.github/workflows/*.yaml) workflows+=("$f") ;;
    ansible/collections/requirements.yml) collection_reqs+=("$f"); ansible_yml+=("$f") ;;
    ansible/playbooks/*.yml) ansible_yml+=("$f"); playbooks+=("$f") ;;
    # Excluded in .ansible-lint, but explicit file arguments bypass exclude_paths.
    ansible/inventory/00-terraform.yml) ;;
    ansible/*.yml) ansible_yml+=("$f") ;;
  esac
done

log=$(mktemp)
trap 'command rm -f "$log"' EXIT

ran=0
failed=0

# sensor <name> <VIOLATION_CODE> <command...>
sensor() {
  local name=$1 code=$2
  shift 2
  ran=$((ran + 1))
  if ! command -v "$1" >/dev/null; then
    echo "INVARIANT_VIOLATION: SENSOR_UNAVAILABLE ($1)"
    failed=$((failed + 1))
    return
  fi
  if "$@" >"$log" 2>&1; then
    echo "PASS: $name"
  else
    echo "INVARIANT_VIOLATION: $code"
    cat "$log"
    echo
    failed=$((failed + 1))
  fi
}

if [ "${#tfstate[@]}" -gt 0 ]; then
  ran=$((ran + 1))
  failed=$((failed + 1))
  echo "INVARIANT_VIOLATION: TFSTATE_STAGED"
  printf '  %s\n' "${tfstate[@]}"
  echo "Unstage with: git restore --staged <file>"
  echo
fi

if [ "$tf_changed" -eq 1 ]; then
  sensor "terraform fmt" TERRAFORM_FMT_FAILED terraform fmt -check -recursive terraform/
  if [ ! -d "$TF_DIR/.terraform" ]; then
    sensor "terraform init" TERRAFORM_INIT_FAILED terraform -chdir="$TF_DIR" init -backend=false -input=false
  fi
  sensor "terraform validate" TERRAFORM_VALIDATE_FAILED terraform -chdir="$TF_DIR" validate -no-color
  sensor "tflint" TFLINT_FAILED tflint --chdir="$TF_DIR" --no-color
  sensor "checkov" CHECKOV_FAILED checkov -d "$TF_DIR" --framework terraform --compact --quiet
fi

if [ "$mode" = all ]; then
  sensor "ansible-lint" ANSIBLE_LINT_FAILED ansible-lint --nocolor
elif [ "${#ansible_yml[@]}" -gt 0 ]; then
  sensor "ansible-lint" ANSIBLE_LINT_FAILED ansible-lint --nocolor "${ansible_yml[@]}"
fi

for pb in "${playbooks[@]}"; do
  sensor "syntax-check $pb" "ANSIBLE_SYNTAX_CHECK_FAILED ($pb)" ansible-playbook --syntax-check "$pb"
done

if [ "${#collection_reqs[@]}" -gt 0 ]; then
  sensor "collection pins" COLLECTION_NOT_PINNED python3 scripts/checks/collection-pins.py "${collection_reqs[@]}"
fi

if [ "${#workflows[@]}" -gt 0 ]; then
  sensor "workflow triggers" SELF_HOSTED_ON_UNTRUSTED_TRIGGER python3 scripts/checks/workflow-triggers.py "${workflows[@]}"
fi

if [ "$deploy_targets" -eq 1 ]; then
  sensor "deploy-targets fixtures" DEPLOY_TARGETS_FAILED scripts/tests/deploy-targets.sh
fi

if [ "$plan_protected" -eq 1 ]; then
  sensor "plan-protected fixtures" PLAN_PROTECTED_FAILED scripts/tests/plan-protected.sh
fi

# The retired all-purpose key must not come back; see credential-separation.
sensor "retired key path" RETIRED_KEY_REFERENCED sh -c '! git grep -n "ssh/Proxmox" -- . ":!openspec" ":!scripts/proof.sh"'

if [ "$ran" -eq 0 ]; then
  echo "proof: nothing to check"
else
  echo "proof: $ran sensor(s), $failed failed"
fi

[ "$failed" -eq 0 ]
