#!/usr/bin/env bash
# Neutral core: stdin {event, tool, input, cwd} -> stdout one decision object.
# Anything that changes real hosts needs a human.
# Returns decision "ask" for terraform apply/destroy and for
# ansible-playbook runs without --check / --syntax-check, and for the gh
# commands that merge a PR or dispatch a workflow. Matching is
# deliberately loose: a false positive costs one click, a miss costs a host.
set -euo pipefail

cmd=$(jq -r '.input.command // empty')

reason=""
while IFS= read -r segment; do
  if grep -qE '(^|[[:space:]/])terraform[[:space:]]' <<<"$segment" &&
     grep -qE '[[:space:]](apply|destroy)([[:space:]]|$)' <<<"$segment"; then
    reason="terraform apply/destroy changes real Proxmox guests"
    break
  fi
  if grep -qE '(^|[[:space:]/])ansible-playbook([[:space:]]|$)' <<<"$segment" &&
     ! grep -qE '[[:space:]](--check|-C|--syntax-check)([[:space:]]|$)' <<<"$segment"; then
    reason="ansible-playbook without --check runs against real hosts"
    break
  fi
  # Merge to main is the deploy (deploy.yml), and so is a dispatch.
  if grep -qE '(^|[[:space:]/])gh[[:space:]]' <<<"$segment"; then
    if grep -qE '[[:space:]]pr[[:space:]]+merge([[:space:]]|$)' <<<"$segment"; then
      reason="merging to main deploys via deploy.yml"
      break
    fi
    if grep -qE '[[:space:]]workflow[[:space:]]+run([[:space:]]|$)' <<<"$segment" ||
       grep -qE '[[:space:]]api[[:space:]].*/(merge|dispatches)([[:space:]?"'"'"']|$)' <<<"$segment"; then
      reason="dispatching or merging via gh can start a deploy"
      break
    fi
  fi
done < <(sed -E 's/(&&|\|\||[;|&])/\n/g' <<<"$cmd")

if [ -z "$reason" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

jq -cn --arg reason "$reason" '{decision: "ask", reason: $reason}'
