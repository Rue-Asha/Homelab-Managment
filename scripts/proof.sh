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
for f in "${files[@]}"; do
  case "$f" in
    *.tfstate|*.tfstate.*) tfstate+=("$f") ;;
  esac
  case "$f" in
    terraform/*) tf_changed=1 ;;
    ansible/playbooks/*.yml) ansible_yml+=("$f"); playbooks+=("$f") ;;
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

if [ "$ran" -eq 0 ]; then
  echo "proof: nothing to check"
else
  echo "proof: $ran sensor(s), $failed failed"
fi

[ "$failed" -eq 0 ]
