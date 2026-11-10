#!/usr/bin/env bash
# PreToolUse gate (Bash), Claude adapter: translates the payload for the neutral core in
# .agents/hooks/core/iac-apply-gate.sh and renders its decision as Claude's permissionDecision.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$here/claude-adapter-lib.sh"

# jq reads the raw stdin, so invalid JSON fails with jq's own message and exit status.
neutral=$(claude_to_neutral) || exit $?
out=$("$here/../../.agents/hooks/core/iac-apply-gate.sh" <<<"$neutral")
render_claude json pre_tool <<<"$out"
