#!/usr/bin/env bash
# Replays the iac-apply-gate goldens (tests/hooks/golden/cases/iac-apply-gate) through the hook
# command that .claude/settings.json wires, in a sandbox: empty HOME (no ~/.agents), a PATH of
# logging stubs for terraform/ansible-playbook/gh plus the system tools the hook needs, no network.
# Each case holds stdin (@PROJ@ = the repo root) and expect/{stdout,stderr,code}, compared byte
# for byte. Run by proof.sh; any stub call fails the run, the hook must never execute them.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1
proj=$PWD
golden=$proj/tests/hooks/golden

sandbox=$(mktemp -d)
trap 'command rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/home" "$sandbox/tmp" "$sandbox/sysbin"

for t in bash sh env cat jq grep sed awk tr cut basename dirname mktemp head tail sort printf timeout; do
  src=$(type -P "$t") || { echo "FAIL: system tool $t not found"; exit 1; }
  ln -s "$src" "$sandbox/sysbin/$t"
done
hook_path=$golden/stubs:$sandbox/sysbin

command=$(jq -r '.hooks.PreToolUse[].hooks[].command | select(contains("iac-apply-gate"))' .claude/settings.json)
[ -n "$command" ] || { echo "FAIL: .claude/settings.json wires no iac-apply-gate hook"; exit 1; }

failed=0
n=0
for dir in "$golden"/cases/iac-apply-gate/*/; do
  dir=${dir%/}
  name=${dir##*/}
  n=$((n + 1))
  : >"$sandbox/stubs.log"
  stdin=$(cat "$dir/stdin"; printf x)
  stdin=${stdin%x}
  printf '%s' "${stdin//@PROJ@/$proj}" >"$sandbox/stdin"
  (cd "$proj" && env -i HOME="$sandbox/home" PATH="$hook_path" TMPDIR="$sandbox/tmp" LANG=C.UTF-8 \
    CLAUDE_PROJECT_DIR="$proj" GOLDEN_STUB_LOG="$sandbox/stubs.log" \
    timeout 60 bash -c "$command") <"$sandbox/stdin" >"$sandbox/stdout" 2>"$sandbox/stderr"
  printf '%s\n' "$?" >"$sandbox/code"
  bad=""
  for x in stdout stderr code; do
    cmp -s "$dir/expect/$x" "$sandbox/$x" || bad="$bad $x"
  done
  [ ! -s "$sandbox/stubs.log" ] || bad="$bad stub-calls"
  if [ -z "$bad" ]; then
    echo "ok: Scenario: iac-apply-gate $name"
  else
    echo "FAIL: Scenario: iac-apply-gate $name (differs:$bad)"
    for x in stdout stderr code; do
      cmp -s "$dir/expect/$x" "$sandbox/$x" || diff -u --label "expect/$x" --label "actual/$x" "$dir/expect/$x" "$sandbox/$x" | head -n 20
    done
    cat "$sandbox/stubs.log"
    failed=1
  fi
done

[ "$n" -gt 0 ] || { echo "FAIL: no golden cases"; exit 1; }
exit "$failed"
