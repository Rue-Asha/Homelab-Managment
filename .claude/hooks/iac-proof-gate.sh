#!/bin/bash
# PreToolUse gate (Bash): no agent commit without proof. Runs scripts/proof.sh
# before any `git commit` and blocks with exit 2, which hands the violations
# back to the agent.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // empty')

sep='(^|[;&|(])[[:space:]]*'
git_cmd='git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+'

grep -qE "${sep}${git_cmd}commit([[:space:]]|$)" <<<"$cmd" || exit 0

# PreToolUse fires before the command runs, so files it stages itself are not
# in the index yet — check everything instead.
mode=--staged
if grep -qE "${sep}${git_cmd}add([[:space:]]|$)" <<<"$cmd" ||
   grep -qE "commit([[:space:]]+[^;&|]*)?[[:space:]](-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|$)" <<<"$cmd"; then
  mode=--all
fi

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"

if ! out=$(scripts/proof.sh "$mode" 2>&1); then
  echo "$out" >&2
  echo >&2
  echo "Commit blocked: fix the violations above and commit again." >&2
  exit 2
fi
