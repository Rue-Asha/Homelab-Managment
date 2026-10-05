verified-at: 56dc636

Sibling worktrees (verified, read-only):
- ci `flow/auto-version-bump` @ 340bc99
- Life-Manager `flow/auto-version-bump` @ 6ae8e8e

## Layer 1

- `scripts/proof.sh --all` (this repo): exit 0
- `bash tests/bump-pin.sh` (ci worktree): exit 0
- `actionlint` (ci worktree): exit 0
- `actionlint .github/workflows/release.yml` (Life-Manager worktree): exit 0

```
PASS: collection pins
PASS: workflow triggers
PASS: deploy-targets fixtures
PASS: plan-protected fixtures
PASS: retired key path
proof: 14 sensor(s), 0 failed
```

## Layer 2

Fixtures print `ok   Scenario: <title> (<assertion>)`; the title matches exactly, with an assertion suffix.

| Scenario | proof | Evidence |
|---|---|---|
| A new tag is bumped | unit + manual | `ci/tests/bump-pin.sh` "Scenario: A new tag is bumped" (stdout, exit, diff, line, rest) ✓; branch push and PR manual |
| The variable line is missing | unit | "Scenario: The variable line is missing" (exit, stderr, untouched) ✓ |
| The value already equals the tag | unit | "Scenario: The value already equals the tag" (stdout, exit, file) ✓ |
| Branch or PR for the tag already exists | manual | checklist |
| A pre-release tag is not bumped | unit | "Scenario: A pre-release tag is not bumped" (stdout, exit, file) ✓ |
| CI runs on the bump PR | manual | checklist |
| The App lacks access | manual | checklist; actionlint clean |
| An older bump PR is still open | manual | checklist |
| The older PR was already merged | manual | checklist |
| CI is green | manual | checklist |
| CI is red | manual | checklist |
| The smoke check fails after the merge | manual | checklist |
| A release is published | manual | checklist; actionlint clean |
| Publish fails | manual | checklist; actionlint clean |
| A release is published after #23 | manual | checklist (blocked on #23) |
| The file is not on main yet | unit | "Scenario: The variable line is missing" ✓; merge-order rule manual |
| Auto-merge can be enabled | manual | checklist |
| Rue sets up a third app | manual | checklist |

Gaps: none.

## Manual checklist

- Create the App, add secrets, enable allow_auto_merge (tasks 4.1-4.3); `gh api repos/Rue-Asha/Homelab-Managment --jq .allow_auto_merge` prints `true`
- Push ci, merge, tag v1.1.0, re-pin Life-Manager caller, merge (4.4, 4.5)
- Tag a Life-Manager release: `bump` runs only after `publish`, opens PR `chore(life-manager): bump to <tag>`, `proof` and `security-baseline` start, auto-merge fires, deploy runs
- Re-run `bump` for the same tag: succeeds, no new PR (branch/PR exists)
- Two consecutive releases: older open bump PR is closed with a comment; an already merged one is left alone
- Wrong App id or missing install: job fails with the token error, no PR under another identity
- Red bump PR stays open with no deploy; failed smoke check rolls back
- After #23: Rues-Arcade hookup and real release; a missing `rues-arcade01/vars.yml` fails naming the file
- Read `docs/release-bump.md` as if adding a third app

## Remaining tasks

4.1-4.5, 5.1-5.4, 6.1-6.3 (human-only or BLOCKED on #23).

## Diffstat

Homelab-Managment (main...flow/auto-version-bump): 8 files, +507 (docs/release-bump.md 140, change artifacts 367).
ci (origin/main...HEAD): .github/actionlint.yaml, .github/workflows/bump-pin.yml, README.md, scripts/bump-pin.sh, tests/bump-pin.sh; 5 files, +267.
Life-Manager (origin/main...HEAD): .github/workflows/release.yml; 1 file, +15.

## Screenshots

none
