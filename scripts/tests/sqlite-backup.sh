#!/usr/bin/env bash
# Fixture tests for the node-side sqlite-backup script and its wiring, run by proof.sh.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

dir=$(mktemp -d)
trap 'command rm -rf "$dir"' EXIT

failed=0

# check <scenario> <command...>   passes when the command exits 0
check() {
  local name=$1
  shift
  if "$@" >"$dir/out" 2>&1; then
    echo "ok: Scenario: $name"
  else
    echo "FAIL: Scenario: $name (exit $?)"
    sed 's/^/  /' "$dir/out"
    failed=1
  fi
}

exit "$failed"
