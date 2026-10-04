#!/bin/bash
# PreToolUse gate (Bash): the agent may not skip the git commit gate
# (.githooks/pre-commit). Blocks with exit 2 any `git commit` carrying
# --no-verify or -n, including inside a short-flag bundle like -anm.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // empty')

# Quoted strings are messages or paths, never flags.
cmd=$(sed -E "s/'[^']*'/Q/g; s/\"([^\"\\\\]|\\\\.)*\"/Q/g" <<<"$cmd")

blocks() {
  local -a words
  read -ra words <<<"$1"
  local i=0
  [ "${words[i]:-}" = git ] || return 1
  i=$((i + 1))
  while [[ "${words[i]:-}" == -* ]]; do
    case "${words[i]}" in
      -C|-c) i=$((i + 2)) ;;
      *) i=$((i + 1)) ;;
    esac
  done
  [ "${words[i]:-}" = commit ] || return 1

  local skip=0 w j c
  for w in "${words[@]:i+1}"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "$w" in
      --) return 1 ;;
      --no-veri*) return 0 ;;
      --message|--file|--author|--date|--template|--reuse-message|--reedit-message|\
      --fixup|--squash|--trailer|--cleanup|--pathspec-from-file) skip=1 ;;
      --*) ;;
      -?*)
        for ((j = 1; j < ${#w}; j++)); do
          c=${w:j:1}
          case "$c" in
            n) return 0 ;;
            # The rest of the bundle is this option's argument; a bare
            # -m/-F/-c/-C/-t takes the next word instead.
            m|F|c|C|t) [ $((j + 1)) -eq ${#w} ] && skip=1; break ;;
            u|S) break ;;
          esac
        done
        ;;
    esac
  done
  return 1
}

while IFS= read -r segment; do
  if blocks "$segment"; then
    echo "Commit blocked: --no-verify / -n skips the commit gate (.githooks/pre-commit)." >&2
    echo "Fix the violations scripts/proof.sh --staged reports and commit without it." >&2
    exit 2
  fi
done < <(sed -E 's/(&&|\|\||[;|&()]|\$\()/\n/g' <<<"$cmd")

exit 0
