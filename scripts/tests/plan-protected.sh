#!/usr/bin/env bash
# Fixture tests for scripts/checks/plan-protected.sh, run by proof.sh. One
# synthetic `terraform show -json` plan per scenario from the
# terraform-provisioning spec.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

dir=$(mktemp -d)
trap 'command rm -rf "$dir"' EXIT

failed=0

# plan <host> <action...>  -> a plan JSON with one resource change
plan() {
  local host=$1
  shift
  jq -n --arg a "module.lxc[\"$host\"].proxmox_virtual_environment_container.this" \
    --argjson actions "$(printf '%s\n' "$@" | jq -R . | jq -s .)" \
    '{resource_changes: [{address: $a, change: {actions: $actions}}]}'
}

# expect <name> <exit code> <host> <action...>
expect() {
  local name=$1 want=$2
  shift 2
  plan "$@" >"$dir/plan.json"
  scripts/checks/plan-protected.sh "$dir/plan.json" >"$dir/out" 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then
    echo "PASS: Scenario: $name"
  else
    echo "FAIL: Scenario: $name (exit $got, wanted $want)"
    cat "$dir/out"
    failed=1
  fi
}

expect "A protected host would be replaced" 1 runner01 delete create
expect "A protected host would be deleted" 1 runner01 delete
expect "An unprotected host is replaced" 0 life-manager01 delete create
expect "A protected host is updated in place" 0 runner01 update

exit "$failed"
