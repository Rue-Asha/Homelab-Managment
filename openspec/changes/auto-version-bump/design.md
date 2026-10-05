## Context

Release flow: tag `vX.Y.Z` in an app repo -> `release.yml` check-tag -> gate -> publish -> new `bump` job -> PR in Homelab-Managment -> `ci.yml` -> auto-merge -> `deploy.yml` -> service playbook -> smoke check (rollback on failure). Most code lands outside this repo, so the build model below deviates from flow's single-repo assumption.

## Goals / Non-Goals

**Goals:** one-line pin bump with no hand edit; idempotent re-runs; one copy of the logic.
**Non-Goals:** as in proposal.md.

## Decisions

From scope.md, as approved:
- GitHub App, not a PAT (not tied to the account, scoped to one repo).
- Auto-merge, not manual merge, with R2 accepted knowingly.
- Reusable workflow in `Rue-Asha/ci`, not per-repo copies.
- Scope is Life-Manager + Rues-Arcade; Rues-Arcade last because PR #23 is unmerged.
- Branch per tag `bump/<variable>-<tag>`, older open PRs closed; no force-push to a bot branch.

Planner decisions:
- **Edit logic in a script, not inline YAML.** `Rue-Asha/ci/scripts/bump-pin.sh <file> <variable> <tag>` holds the four S1 edges so they get fixture tests (`Rue-Asha/ci/tests/bump-pin.sh`, same style as `scripts/tests/deploy-targets.sh` here). The workflow checks out `Rue-Asha/ci` at `github.job_workflow_sha` to get it (callers pin the workflow by SHA, so the script is the matching one). Inline YAML would be smaller but leaves the edges provable only on a live release; if `job_workflow_sha` misbehaves on the first run, inlining the script body is the fallback.
- **Inputs/secrets**: inputs `app` (name for the PR title, e.g. `life-manager`), `host_vars_path`, `variable`, `tag`, `target_repo` (default `Rue-Asha/Homelab-Managment`); secrets `app_id`, `app_private_key`, passed explicitly (no `secrets: inherit`). Per app repo the secrets are named `HOMELAB_BUMP_APP_ID`, `HOMELAB_BUMP_APP_KEY`.
- **Token**: `actions/create-github-app-token`, pinned to a full SHA (the baseline's zizmor config demands hash pins for every `uses:`), scoped to `owner`/`repositories: Homelab-Managment`. No fallback to `GITHUB_TOKEN`: a failed token step fails the job (S2). The App needs Contents RW, Pull requests RW, Metadata R on Homelab-Managment only.
- **Pre-release**: a tag with a `-suffix` (`v1.2.3-rc1`) makes the script print `skipped` and the job end green without a PR.
- **Idempotence order**: skipped -> value already equals tag -> open/merged PR or branch `bump/<variable>-<tag>` exists -> otherwise edit, push, open PR, enable auto-merge (`gh pr merge --auto --squash`), close older open `bump/<variable>-*` PRs.
- **R6 resolved**: `Rue-Asha/ci` is public, so other repos can call its reusable workflows with no access-setting change (the "access" policy API only applies to private/internal repos).
- **R5 resolved**: `ansible/roles/rues_arcade/tasks/verify.yml` on `origin/feat/rues-arcade` has the same smoke check and rollback as `roles/life_manager/tasks/verify.yml` (uri through the proxy with retries, rescue points `current` back to the previous release, restarts, fails the play). S6 stays auto-merge.

### Scope corrections found while planning (flag at Gate 1)

- **R4 is partly wrong.** `main` is already protected by a ruleset named `main` (active, no bypass actors): PR required with 0 approvals, required checks `proof`, `security-baseline / workflow-lint`, `security-baseline / secret-scan`, `security-baseline / dependency-review` (GitHub Actions), `strict_required_status_checks_policy: true`. Only `allow_auto_merge` is off. S7 therefore reduces to "enable allow_auto_merge"; the required checks are four, not two (`proof`, `security-baseline`), and need no edit. Allowed merge methods already include squash.
- **Strict policy**: a bump PR must be up to date with `main` to merge. If another PR merges first, the bump PR goes behind and auto-merge waits until someone updates it. Accepted; documented in `docs/release-bump.md` (update-branch, or re-run and let the older-PR cleanup supersede). Not changed here.

### Cross-repo build and verification model

flow assumes one repo. Units that touch sibling repos are built like this:
- The builder creates a worktree of the sibling from `origin/main`: `git -C ../<repo> worktree add ../<repo>-auto-version-bump -b flow/auto-version-bump origin/main` (the sibling checkouts sit on other branches, `Life-Manager` on `feat/uni-notes-todo-rows`, `Rues-Arcade` on `flow/add-three-games`; they are never touched). Commits go on that branch, local only, message `flow(auto-version-bump): <what>` with the attribution trailer.
- The unit's checkboxes and any notes are committed in this repo on the unit branch as usual (tasks.md only); the sibling commit hash is written into the task line.
- Nothing is pushed, no PR opened: that leaves the machine, so Rue pushes and opens the PR per repo (human task in group 4).
- Proof available locally: `actionlint` (installed at `/usr/bin/actionlint`) over the changed workflow files; the fixture script `bash tests/bump-pin.sh` in `ci`; `scripts/proof.sh --all` in this repo. Not installed, so not used: `zizmor`, `shellcheck`, `yamllint`, `act`, `bats`. In CI, `security-baseline / workflow-lint` runs actionlint + zizmor on each repo's PR, so zizmor findings (e.g. unpinned `uses:`) show up there; the builder pins every `uses:` to a SHA by hand to avoid them.
- Everything that needs a real tag, the App or GitHub merge behaviour is `manual` and is confirmed on the first real release (group 5).
- Ordering: callers pin `Rue-Asha/ci` by the SHA of the merge commit on `ci` main. So the Life-Manager/Rues-Arcade units write a placeholder-free but provisional pin (the local `ci` commit SHA) and the human step in group 4 re-pins to the real SHA/tag after the `ci` PR is merged and tagged.

## Contracts

Shared between group 1 (ci), groups 2, 3 and 6:

- Workflow: `Rue-Asha/ci/.github/workflows/bump-pin.yml` (`on: workflow_call`).
  - inputs (all strings): `app` (required), `host_vars_path` (required, relative to the target repo root, e.g. `ansible/inventory/host_vars/life-manager01/vars.yml`), `variable` (required, e.g. `life_manager_version`), `tag` (required), `target_repo` (optional, `owner/name`, default `Rue-Asha/Homelab-Managment`; the App token's owner and repository are split from it, so it has to stay an input).
  - secrets: `app_id`, `app_private_key` (both required).
  - job name `bump`; job-level `concurrency: {group: bump-<variable>, cancel-in-progress: false}`; only `changed` goes on to push and open a PR.
- Caller job (app repo `release.yml`):
  ```yaml
  bump:
    needs: publish
    permissions:
      contents: read
    uses: Rue-Asha/ci/.github/workflows/bump-pin.yml@<sha> # vX.Y.Z
    with:
      app: life-manager
      host_vars_path: ansible/inventory/host_vars/life-manager01/vars.yml
      variable: life_manager_version
      tag: ${{ github.ref_name }}
    secrets:
      app_id: ${{ secrets.HOMELAB_BUMP_APP_ID }}
      app_private_key: ${{ secrets.HOMELAB_BUMP_APP_KEY }}
  ```
- Script: `scripts/bump-pin.sh <file> <variable> <tag>`. Prints exactly one of `changed`, `unchanged`, `skipped` or `skipped: <tag> is older than the pinned <pin>` on stdout and exits 0 (the pin only moves upward, compared as `vMAJOR.MINOR.PATCH`, numeric per component, optional leading `v`; a tag or pin of another form exits 1 with `bump-pin: <file>: <variable>: <value> is not a version (vMAJOR.MINOR.PATCH)`); for a missing variable it exits 1 with `bump-pin: <file>: <variable> not found` on stderr, for a missing file `bump-pin: <file>: file not found`. Only the value on the line `^<variable>: ` is replaced, literally; quotes and a trailing comment stay, rest of the file byte-identical.
- Script: `scripts/ensure-bump-pr.sh` (env `TARGET_REPO APP VARIABLE TAG`, run in the target checkout after `changed`). Does only the missing steps: push the branch if absent, open the PR if absent, enable auto-merge if off, close superseded PRs (open `bump/<variable>-<tag>` PRs whose parsed tag is older than ours; newer and unparseable ones stay). A merged or closed PR for the tag is a no-op.
- Branch `bump/<variable>-<tag>`; PR title `chore(<app>): bump to <tag>`; commit message equal to the PR title.

## Risks / Trade-offs

- R1 (accepted, scope): an App-initiated auto-merge should trigger `deploy.yml`; confirmed on the first real release.
- R2 (accepted): a compromised app repo or App key can deploy by editing one line; the App writes only to this repo, and the `infrastructure` approval still gates Terraform.
- R3 (accepted): a rolled-back deploy leaves the pin ahead of the host.
- R4 corrected above; R5, R6 resolved above.
- Trade-off: the script adds a checkout step and a `job_workflow_sha` dependency in exchange for fixture-proven edge cases.
- The bigger design (Renovate-style bot or a Homelab-side check on the diff) would buy a verified one-line diff; out of scope (R2).
