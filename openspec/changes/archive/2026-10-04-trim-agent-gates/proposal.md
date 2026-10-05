## Why

`ci-homelab` made CI the merge authority: `main` only takes a PR with
`proof` (`scripts/proof.sh --all`) green and up to date. A commit that skipped
the pre-commit hook can no longer reach `main`, so the agent-side
`--no-verify` gate guards nothing CI doesn't already guard.

`cd-homelab` moved the deploy: merging to `main`, or dispatching
`deploy.yml`, now runs the `03_SERVICES` playbooks on real hosts. The
real-host gate still only knows `ansible-playbook` and `terraform`, so the
commands that deploy today pass it unasked.

## What Changes

- Remove `.claude/hooks/iac-no-verify-gate.sh` and its registration. The
  pre-commit hook stays as fast local feedback; CI is the backstop.
- The real-host gate also asks before `gh pr merge`, `gh workflow run`, and
  `gh api` calls that merge a PR or dispatch a workflow.

## Non-Goals

- Changing the pre-commit hook or `scripts/proof.sh`.
- Gating merges made outside Claude Code (the GitHub UI is Rue's call).

## Done criteria

- [ ] `.claude/settings.json` registers only `iac-apply-gate.sh`.
- [ ] `gh pr merge 12 --merge` and `gh workflow run deploy.yml` get an `ask`;
      `gh pr view 12` passes without one.

## Appetite

Under an hour.

## Capabilities

### Modified Capabilities
- `agent-harness`: the no-verify gate is dropped; the real-host gate covers
  the deploy triggers.

## Impact

`.claude/hooks/iac-apply-gate.sh`, `.claude/hooks/iac-no-verify-gate.sh`
(deleted), `.claude/settings.json`, `.claude/CLAUDE.md`, `README.md`.
