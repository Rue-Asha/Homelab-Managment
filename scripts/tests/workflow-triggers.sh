#!/usr/bin/env bash
# Fixture tests for scripts/checks/workflow-triggers.py, run by proof.sh. One
# synthetic workflow per scenario from the ci-pipeline spec.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

dir=$(mktemp -d)
trap 'command rm -rf "$dir"' EXIT

failed=0

# expect <scenario> <pass|fail> <trigger> <runs-on yaml>
expect() {
  local name=$1 want=$2 trigger=$3 runs_on=$4 status got
  printf 'on: %s\njobs:\n  j:\n    runs-on: %s\n    steps: []\n' "$trigger" "$runs_on" >"$dir/w.yml"
  python3 scripts/checks/workflow-triggers.py "$dir/w.yml" >/dev/null 2>&1
  status=$?
  got=pass
  [ "$status" -eq 0 ] || got=fail
  if [ "$got" = "$want" ]; then
    echo "ok: $name"
  else
    echo "FAIL: $name (want $want, got $got)"
    failed=1
  fi
}

expect "Scenario: deploy label under a PR trigger" fail pull_request '[self-hosted, homelab-deploy]'
expect "Scenario: check label under a PR trigger" pass pull_request '[self-hosted, homelab-check]'
expect "Scenario: mixed labels under a PR trigger" fail pull_request '[self-hosted, homelab-check, homelab-deploy]'
expect "Scenario: expression under a PR trigger" fail pull_request '${{ vars.RUNNER }}'
expect "bare deploy label under a PR trigger" fail pull_request 'homelab-deploy'
expect "bare check label under a PR trigger" fail pull_request 'homelab-check'
expect "other self-hosted label under a PR trigger" fail pull_request '[self-hosted, linux]'
expect "hosted runner under a PR trigger" pass pull_request 'ubuntu-24.04'
expect "check label under another untrusted trigger" pass issue_comment '[self-hosted, homelab-check]'
expect "deploy label under a list of triggers with a PR" fail '[push, pull_request]' '[self-hosted, homelab-deploy]'
expect "deploy label under trusted triggers" pass '[push, workflow_dispatch]' '[self-hosted, homelab-deploy]'

[ "$failed" -eq 0 ]
