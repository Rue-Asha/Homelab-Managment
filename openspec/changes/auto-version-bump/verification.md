verified-at: f665e3b

Sibling worktrees (verified, read-only):
- ci `flow/auto-version-bump` @ e1613f7 (includes e08a653)
- Life-Manager `flow/auto-version-bump` @ 6ae8e8e

## Layer 1

Run with a short `TMPDIR` (/tmp/claude-1001/t); a long one breaks terraform's plugin socket (that caused the red in round 2). Lock file and `.terraform` were clean before the run and restored/removed after it, never staged.

- `scripts/proof.sh --all` (this repo): exit 0
- `bash tests/bump-pin.sh` (ci worktree): exit 0
- `bash tests/ensure-bump-pr.sh` (ci worktree): exit 0
- `actionlint` (ci worktree): exit 0
- `actionlint .github/workflows/release.yml` (Life-Manager worktree): exit 0

```
PASS: syntax-check ansible/playbooks/03_SERVICES/pihole.yml
PASS: collection pins
PASS: workflow triggers
PASS: deploy-targets fixtures
PASS: plan-protected fixtures
PASS: retired key path
proof: 15 sensor(s), 0 failed
```

## Layer 2

Fixtures print `ok   Scenario: <title> (<assertion>)`; counts are ok lines across `tests/bump-pin.sh` and `tests/ensure-bump-pr.sh`; no non-ok lines.

| Scenario | proof | Evidence |
|---|---|---|
| A new tag is bumped | unit + manual | "Scenario: A new tag is bumped" 10 ok ✓; branch push and PR manual |
| The line has quotes, a comment or special characters | unit | "Scenario: The line has quotes, a comment or special characters" 4 ok ✓ |
| The value is not a plain or quoted token | unit | "Scenario: The value is not a plain or quoted token" 20 ok ✓ |
| The tag is not a safe YAML scalar | unit | "Scenario: The tag is not a safe YAML scalar" 36 ok ✓ |
| The variable line is missing | unit | "Scenario: The variable line is missing" 3 ok ✓ |
| The value already equals the tag | unit | "Scenario: The value already equals the tag" 6 ok ✓ |
| Branch or PR for the tag already exists | unit + manual | "Scenario: Branch or PR for the tag already exists" 4 ok ✓ (stubbed gh); real re-run manual |
| A previous run stopped before the PR or auto-merge | unit + manual | "Scenario: A previous run stopped before the PR or auto-merge" 9 ok ✓ (stubbed gh); real failure manual |
| A pre-release tag is not bumped | unit | "Scenario: A pre-release tag is not bumped" 3 ok ✓ |
| CI runs on the bump PR | manual | checklist |
| The App lacks access | manual | checklist; actionlint clean |
| An older bump PR is still open | unit + manual | "Scenario: An older bump PR is still open" 5 ok ✓ (stubbed gh); two real PRs manual |
| The current PR is already merged but an older one is still open | unit | "Scenario: An older bump PR is still open (merged current PR: exit / older closed / only the older)" ✓ |
| The older PR was already merged | manual | checklist |
| CI is green | manual | checklist |
| CI is red | manual | checklist |
| The smoke check fails after the merge | manual | checklist |
| A release is published | manual | checklist; actionlint clean |
| Publish fails | manual | checklist; actionlint clean |
| A release is published after #23 | manual | checklist (blocked on #23) |
| The file is not on main yet | unit + manual | "Scenario: The file is not on main yet" 2 ok ✓; merge-order rule manual |
| Auto-merge can be enabled | manual | checklist |
| Rue sets up a third app | manual | checklist |

Gaps: none.

## Manual checklist

- Create the App, add secrets, enable allow_auto_merge (tasks 4.1-4.3); `gh api repos/Rue-Asha/Homelab-Managment --jq .allow_auto_merge` prints `true`
- Push ci, merge, tag v1.1.0, re-pin Life-Manager caller, merge (4.4, 4.5)
- Tag a Life-Manager release: `bump` runs only after `publish`, opens PR `chore(life-manager): bump to <tag>`, `proof` and `security-baseline` start, auto-merge fires, deploy runs
- Re-run `bump` for the same tag (merged, or open with auto-merge): succeeds, no new PR
- Break a run after the push (or disable auto-merge on the PR) and re-run: the missing PR / auto-merge is added
- Two consecutive releases: older open bump PR is closed with a comment; an already merged one is left alone
- Wrong App id or missing install: job fails with the token error, no PR under another identity
- Red bump PR stays open with no deploy; failed smoke check rolls back
- After #23: Rues-Arcade hookup and real release; a missing `rues-arcade01/vars.yml` fails naming the file
- Read `docs/release-bump.md` as if adding a third app

## Diffstat

This repo, `main...flow/auto-version-bump`: 9 files, 620 insertions (docs/release-bump.md, openspec/changes/auto-version-bump/*).

ci vs origin/main: 7 files, 517 insertions (.github/actionlint.yaml, .github/workflows/bump-pin.yml, README.md, scripts/bump-pin.sh, scripts/ensure-bump-pr.sh, tests/bump-pin.sh, tests/ensure-bump-pr.sh).

Life-Manager vs origin/main: 1 file, 15 insertions (.github/workflows/release.yml).

Screenshots: none.

Notes: `03_SERVICES` reference at openspec/changes/auto-version-bump/tasks.md:30 (5.2, `03_SERVICES/life-manager.yml`); no `02_BASE_CONFIGURATION` references.
