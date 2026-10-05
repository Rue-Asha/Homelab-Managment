#!/usr/bin/env bash
# Terraform steps of .github/workflows/deploy.yml, on the runner. The job log is
# public, so nothing here prints plan or state values: only `address action`
# lines, and a generic message when a Terraform command fails. Use the
# workstation to read the details.
#
#   scripts/tf-ci.sh plan     init, plan, summarise, refuse to destroy runner01/state01
#   scripts/tf-ci.sh apply    apply the plan made for this commit, pin new guests' host keys
#   scripts/tf-ci.sh render   init and render ansible/inventory/00-terraform.yml
#
# Needs HOMELAB_TERRAFORM_ENV (set by the runner's .env) and GITHUB_SHA.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

tf_dir=terraform/environments/homelab
plans=$HOME/.cache/homelab/tf-plans
state=$HOME/.local/state/homelab/terraform.tfstate
known_hosts=$HOME/.ssh/known_hosts

: "${HOMELAB_TERRAFORM_ENV:?not set: the runner .env hands it to jobs}"
install -d -m 700 "$(dirname "$state")"
set -a
# shellcheck disable=SC1090
. "$HOMELAB_TERRAFORM_ENV"
set +a

tf() { terraform -chdir="$tf_dir" "$@"; }

# quiet <command...>: output withheld, because Terraform errors can embed values.
quiet() {
  local log
  log=$(mktemp)
  if "$@" >"$log" 2>&1; then
    command rm -f "$log"
    return 0
  fi
  command rm -f "$log"
  echo "::error::'${*:1:3}' failed; output withheld because the log is public. Reproduce on the workstation." >&2
  return 1
}

cmd=${1:-}
case "$cmd" in
  plan)
    : "${GITHUB_SHA:?}"
    install -d -m 700 "$plans"
    plan=$plans/$GITHUB_SHA.tfplan
    quiet tf init -input=false -reconfigure -backend-config="path=$state"
    quiet tf plan -input=false -no-color -out="$plan"
    tf show -json "$plan" >"$plan.json"
    jq -r '.resource_changes[]? | select(.change.actions != ["no-op"]) | "\(.address) \(.change.actions | join(","))"' "$plan.json"
    scripts/checks/plan-protected.sh "$plan.json"
    ;;

  apply)
    : "${GITHUB_SHA:?}"
    plan=$plans/$GITHUB_SHA.tfplan
    [ -f "$plan" ] || { echo "::error::no saved plan for $GITHUB_SHA" >&2; exit 1; }
    quiet tf init -input=false -reconfigure -backend-config="path=$state"
    quiet tf apply -input=false -no-color "$plan"

    # Guests this apply created: pin their host keys now, the same trust moment
    # deploy_runner.yml uses. Keys already pinned are never overwritten.
    mapfile -t created < <(jq -r '.resource_changes[]? | select(.change.actions == ["create"]) | .address
      | capture("^module\\.lxc\\[\"(?<n>[^\"]+)\"\\]\\.proxmox_virtual_environment_container\\.this$").n' "$plan.json")
    if [ "${#created[@]}" -gt 0 ]; then
      touch "$known_hosts"
      for name in "${created[@]}"; do
        ip=$(tf output -json lxc_hosts | jq -r --arg n "$name" '.[$n].ipv4 | split("/")[0]')
        ssh-keygen -F "$ip" -f "$known_hosts" >/dev/null && continue
        key=""
        for _ in $(seq 20); do
          key=$(ssh-keyscan -T 3 -t ed25519 "$ip" 2>/dev/null) && [ -n "$key" ] && break
          sleep 3
        done
        [ -n "$key" ] || { echo "::error::no SSH host key from $name; deploy to it will fail" >&2; exit 1; }
        echo "$key" >>"$known_hosts"
        echo "pinned host key for $name"
      done
    fi
    command rm -f "$plan" "$plan.json"
    ;;

  render)
    quiet tf init -input=false -reconfigure -backend-config="path=$state"
    scripts/render-inventory.sh
    # The workstation reads this copy over SSH (scripts/fetch-inventory.sh).
    install -d -m 755 "$HOME/.cache/homelab"
    install -m 644 ansible/inventory/00-terraform.yml "$HOME/.cache/homelab/00-terraform.yml"
    ;;

  *)
    echo "usage: scripts/tf-ci.sh plan|apply|render" >&2
    exit 64
    ;;
esac
