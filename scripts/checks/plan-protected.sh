#!/usr/bin/env bash
# Fails when a Terraform plan would delete or replace a protected host.
#
#   scripts/checks/plan-protected.sh <plan.json>    from `terraform show -json`
#
# PROTECTED_HOSTS (space separated, default "runner01") names the hosts Terraform must never
# destroy: the runner that applies and holds the state.
# Exit 0: none is deleted or replaced. Exit 1: one is. Exit 64: usage.

set -euo pipefail

[ "$#" -eq 1 ] || { echo "usage: plan-protected.sh <plan.json>" >&2; exit 64; }

protected=${PROTECTED_HOSTS:-runner01}

hits=$(jq -r --arg hosts "$protected" '
  ($hosts | split(" ")) as $names
  | .resource_changes[]?
  | select(.change.actions | index("delete"))
  | select(.address | test("^module\\.(lxc|vm)\\[\"(" + ($names | join("|")) + ")\"\\]"))
  | "\(.address) \(.change.actions | join(","))"
' "$1")

if [ -n "$hits" ]; then
  echo "plan would destroy a protected host:" >&2
  echo "$hits" | sed 's/^/  /' >&2
  exit 1
fi
