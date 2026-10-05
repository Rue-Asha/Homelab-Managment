verified-at: 8cb4935

Sibling worktrees (verified, read-only):
- ci `flow/auto-version-bump` @ e061c74
- Life-Manager `flow/auto-version-bump` @ 6ae8e8e

## Layer 1

Short `TMPDIR` (/tmp/claude-1001/t). Worktrees were clean before the run; the lock file was restored and `.terraform` removed after it, never staged.

- `scripts/proof.sh --all` (this repo): exit 0
- `openspec validate auto-version-bump --strict` (this repo): valid
- `bash tests/bump-pin.sh` (ci worktree): exit 0
- `bash tests/ensure-bump-pr.sh` (ci worktree): exit 0
- `actionlint` (ci worktree): exit 0
- `actionlint .github/workflows/release.yml` (Life-Manager worktree): exit 0

```
PASS: collection pins
PASS: workflow triggers
PASS: deploy-targets fixtures
PASS: plan-protected fixtures
PASS: retired key path
proof: 15 sensor(s), 0 failed
```

## Layer 2

Fixtures print `ok   Scenario: <title> (<assertion>)`; counts are ok lines across `tests/bump-pin.sh` and `tests/ensure-bump-pr.sh`; no non-ok lines.

New since round 4: "The variable is set more than once" (bump-pin.sh, 4 ok), "The current PR is already merged but an older one is still open" (now an unchanged-result fixture, 3 ok, plus the workflow-text assertion). Counts changed: "A new tag is bumped" 10 -> 12, "A tag older than the pinned version is not bumped" 7 -> 13, "A version that cannot be compared fails" 28 -> 30, "Branch or PR for the tag already exists" 4 -> 8, "The value already equals the tag" 6 -> 8, "An older bump PR is still open" 5 -> 2 plain + 3 merged-current.

| Scenario | proof | Evidence |
|---|---|---|
| A new tag is bumped | unit + manual | "Scenario: A new tag is bumped" 12 ok ✓; branch push and PR manual |
| The line has quotes, a comment or special characters | unit | "Scenario: The line has quotes, a comment or special characters" 3 ok ✓ |
| The value is not a plain or quoted token | unit | "Scenario: The value is not a plain or quoted token" 20 ok ✓ |
| The tag is not a safe YAML scalar | unit | "Scenario: The tag is not a safe YAML scalar" 36 ok ✓ |
| The variable line is missing | unit | "Scenario: The variable line is missing" 3 ok ✓ |
| The variable is set more than once (new) | unit | "Scenario: The variable is set more than once" 4 ok ✓ (exit, stdout, stderr, untouched) |
| The value already equals the tag | unit | "Scenario: The value already equals the tag" 8 ok ✓ (6 bump-pin, 2 ensure-bump-pr: unchanged without PR) |
| Branch or PR for the tag already exists | unit + manual | "Scenario: Branch or PR for the tag already exists" 8 ok ✓ (stubbed gh); real re-run manual |
| A previous run stopped before the PR or auto-merge | unit + manual | "Scenario: A previous run stopped before the PR or auto-merge" 9 ok ✓ (stubbed gh); real failure manual |
| A pre-release tag is not bumped | unit | "Scenario: A pre-release tag is not bumped" 3 ok ✓ |
| A tag older than the pinned version is not bumped | unit + manual | "Scenario: A tag older than the pinned version is not bumped" 13 ok ✓; real older-tag re-run manual |
| A version that cannot be compared fails | unit | "Scenario: A version that cannot be compared fails" 30 ok ✓ |
| Two releases are tagged close together | manual + actionlint | `concurrency: group: bump-${{ inputs.variable }}, cancel-in-progress: false` at ci `.github/workflows/bump-pin.yml:62-64`; actionlint clean; needs two real releases |
| CI runs on the bump PR | manual | checklist |
| The App lacks access | manual | checklist; actionlint clean |
| An older bump PR is still open | unit + manual | "Scenario: An older bump PR is still open" 2 ok ✓ (stubbed gh) + 3 ok "(merged current PR: ...)" ✓; two real PRs manual |
| Only older bump PRs are superseded | unit + manual | "Scenario: Only older bump PRs are superseded" 7 ok ✓ (stubbed gh); real re-run manual |
| The current PR is already merged but an older one is still open (new proof) | unit | "Scenario: The current PR is already merged but an older one is still open" 3 ok ✓ (unchanged result: exit, older closed, no create/merge/push); "workflow passes the bump-pin result to ensure-bump-pr.sh unconditionally" ok ✓ (grep on bump-pin.yml:113) |
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

Gaps: none. Note: the workflow-text assertion is a grep for `ensure-bump-pr.sh "$result"` at end of line; it does not execute the workflow, so that the step actually runs on `unchanged` is covered by text and actionlint only.

## Manual checklist

- Create the App, add secrets, enable allow_auto_merge (tasks 4.1-4.3); `gh api repos/Rue-Asha/Homelab-Managment --jq .allow_auto_merge` prints `true`
- Push ci, merge, tag v1.1.0, re-pin Life-Manager caller, merge (4.4, 4.5)
- Tag a Life-Manager release: `bump` runs only after `publish`, opens PR `chore(life-manager): bump to <tag>`, `proof` and `security-baseline` start, auto-merge fires, deploy runs
- Re-run `bump` for the same tag (merged, or open with auto-merge): succeeds, no new PR
- Break a run after the push (or disable auto-merge on the PR) and re-run: the missing PR / auto-merge is added
- Two consecutive releases: older open bump PR is closed with a comment; an already merged one is left alone
- After the newer bump PR merged, re-run the newer tag's `bump` with the older PR still open: the older PR is closed, no new PR
- Re-run an older tag's job after `main` moved on: no downgrade PR, newer open PRs are not closed
- Tag two releases within seconds: the second `bump` waits for the first, nothing is cancelled
- Wrong App id or missing install: job fails with the token error, no PR under another identity
- Red bump PR stays open with no deploy; failed smoke check rolls back
- After #23: Rues-Arcade hookup and real release; a missing `rues-arcade01/vars.yml` fails naming the file
- Read `docs/release-bump.md` as if adding a third app

## Diffstat

This repo, `main...flow/auto-version-bump`: 9 files, 709 insertions (docs/release-bump.md, openspec/changes/auto-version-bump/*).

ci vs origin/main: 8 files, 704 insertions (.github/actionlint.yaml, .github/workflows/bump-pin.yml, README.md, scripts/bump-pin.sh, scripts/ensure-bump-pr.sh, scripts/version.sh, tests/bump-pin.sh, tests/ensure-bump-pr.sh).

Life-Manager vs origin/main: 1 file, 15 insertions (.github/workflows/release.yml) (not re-measured this round, tip unchanged at 6ae8e8e).

Screenshots: none.

Notes: `03_SERVICES` reference at openspec/changes/auto-version-bump/tasks.md:30 (5.2, `03_SERVICES/life-manager.yml`); no `02_BASE_CONFIGURATION` references.

## Review

Three rounds (verifier + fresh-context reviewer, fixer after rounds 1 and 2). Round 3 stopped at the round limit; the open items are listed for the human at Gate 2.

### Resolved in rounds 1 and 2
- Partial failure left a branch without PR or without auto-merge; a re-run now completes the missing steps (`ensure-bump-pr.sh`).
- Tag with `&` or `|` broke the rewrite; the tag and variable now reach perl through the environment.
- Quotes and trailing comments on the pin line are preserved; "unchanged" is detected for those forms.
- `jq` filter uses `--arg`; a missing file has its own error and its own test.
- `target_repo` input kept and documented in design.md and the spec.
- A value that cannot be rewritten (`""`, `{{ x }}`) and an unsafe tag now fail loudly.
- The supersede loop also runs before the MERGED early exit.
- Weak tests tightened (stub pins `--head`, `--state all`, JSON fields; pushed commit content; no second push on re-run from a fresh clone).
- `create-github-app-token` gets explicit `permission-contents` and `permission-pull-requests`.
- `Rue-Asha/ci` is public (checked with gh), so the unauthenticated checkout of it works.

### Open after round 3 (not fixed; the human decides)
- **Version ordering**: no check that the new tag is higher than the pinned one. A re-run of an older tag's job after `main` moved on opens a downgrade PR that auto-merges and deploys the older version. Out-of-order releases (a `v0.2.9` hotfix after `v0.3.0`) behave the same. The supersede step also closes newer open bump PRs when an older tag's job re-runs, and a closed PR is never reopened. Recommended: bump only upward and supersede only older PRs.
- **PR closed without merge** (by hand or superseded): the job exits 0 "nothing to do" while `main` still pins the old version. Not in the spec; documented in docs/release-bump.md ("tag again").
- **No `concurrency` group**: two releases tagged close together can close each other's PRs. Recommended: one group per variable.
- **Hyphenated stable tags** (`v1.2.3-hotfix`) count as pre-releases and are skipped silently.
- Low: quoted value with spaces or `#` passes the value check but is not rewritten (prints `unchanged`); tags `&x`, `*x` and an empty tag are written as YAML anchor, alias and null; test gaps (open PR with auto-merge does not assert "no push"; `&`/`|`/single-quote "unchanged" cases).
- Manual only, by design: everything that needs real GitHub (PR creation, CI on the bot PR, auto-merge, deploy after merge, R1).

### Round 4 (after fixer round 3, approved by the human beyond the 3-round limit)
Resolved: version ordering (only upward; older tag -> `skipped`, no PR; unparseable version fails loudly; supersede closes only older PRs) and a per-variable `concurrency` group. Changed scenario: "The line has quotes, a comment or special characters" no longer covers a tag containing `&` or `|`; such a tag is now an unparseable version and fails (justified by the new "A version that cannot be compared fails" scenario; the literal-substitution path is no longer exercised with hostile characters).

Open after round 4:
- **[bug] Supersede unreachable from the workflow after a merge**: the workflow calls `ensure-bump-pr.sh` only when `bump-pin.sh` prints `changed`. Once the bump PR has merged, `main` pins the tag, the script prints `unchanged`, and the supersede step never runs. If closing the older PR failed in the first run, a re-run of the newer tag never retries it. Unit tests call the script directly and do not show this. Recommended: the workflow also runs the supersede step on `unchanged` (supersede only, no PR creation).
- Low: version compare uses bash `10#` arithmetic and overflows on very long numbers (`v0.0.18446744073709551617` is judged older than `v0.0.5`); duplicated in `older_than_current`. A file with two `<variable>:` lines gets both rewritten.
- PR closed without merge is a silent no-op (known, documented); `.[0]` of `gh pr list --head ... --state all` may pick the wrong PR when an old closed and a new open PR share a head.
- Test gaps: open PR with auto-merge does not assert "no push"; no tests for very long numbers, `v0.03.0` or a pre-release pin; `--body`/`--repo` of `gh pr create` not asserted.
- Known, human-only: the Life-Manager caller is pinned to the early local ci commit `340bc99` with a `# v1.1.0` comment; no `v1.1.0` tag exists yet (only `v1.0.0`). Task 4.5 re-pins it to the final merged ci SHA after 4.4. Until then the caller would run the old workflow.

### Round 5 (fixer round 4, human asked to fix all surfaced bugs)
Resolved: supersede after a merge (the workflow always passes the `bump-pin.sh` result to `ensure-bump-pr.sh`, which supersedes on `unchanged` when the tag's PR is MERGED), long-number overflow (digit-string compare in `scripts/version.sh`), PR pick when several share a head (open, then merged, then the rest), test gaps (no-push, `gh pr create` repo/head/body, long numbers, `v0.03.0`, pre-release pin). Deviation, to be confirmed by the human: a file with the variable on more than one line now fails (`<variable> is set more than once`) instead of rewriting both; new scenario "The variable is set more than once".

Verifier: Layer 1 green, no gaps. Reviewer (fresh context): no weakened tests, no weak tests, no correctness findings.

Open after round 5 (known, not fixed):
- A tag's PR closed without merge: a re-run exits 0 and does nothing (documented in docs/release-bump.md, "tag again"); no test pins it.
- A tag without a leading `v` (`1.2.4` against `v1.2.3`) is accepted and written as-is, so the pin loses its `v`. A test pins this; no scenario asks for it.
- The step ordering "workflow always runs the supersede step" is proved by a text grep on `bump-pin.yml:113` plus actionlint, not by running the workflow.
- Manual only: everything that needs real GitHub, as in the checklist above.
