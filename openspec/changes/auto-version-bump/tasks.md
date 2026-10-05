## 1. Reusable bump workflow in Rue-Asha/ci
> unit: depends=none · scope=S1,S2,S3,S4 · files=../ci/scripts/bump-pin.sh, ../ci/tests/bump-pin.sh, ../ci/.github/workflows/bump-pin.yml, ../ci/README.md
- [ ] 1.1 In a worktree of `../ci` (`git -C ../ci worktree add ../ci-auto-version-bump -b flow/auto-version-bump origin/main`) write `tests/bump-pin.sh` with fixtures "Scenario: A new tag is bumped", "…The variable line is missing", "…The value already equals the tag", "…A pre-release tag is not bumped" (fails first)
- [ ] 1.2 Write `scripts/bump-pin.sh` per the Contracts in design.md until `bash tests/bump-pin.sh` is green
- [ ] 1.3 Write `.github/workflows/bump-pin.yml` (`workflow_call`, inputs/secrets per Contracts): checkout of the target repo with the App token (`actions/create-github-app-token`, SHA-pinned, no `GITHUB_TOKEN` fallback), checkout of `Rue-Asha/ci` at `github.job_workflow_sha`, idempotence checks for branch/PR, push `bump/<variable>-<tag>`, `gh pr create` with title `chore(<app>): bump to <tag>`, `gh pr merge --auto --squash`, close older open `bump/<variable>-*` PRs
- [ ] 1.4 `actionlint` over the new workflow is clean and every `uses:` is a full SHA with a version comment (SHAs looked up read-only with `gh api`)
- [ ] 1.5 Add a `bump-pin` section to `../ci/README.md` (inputs, secrets, call example, job name `bump` is interface); commit locally on the sibling branch, record the commit hash here. Do not push

## 2. docs/release-bump.md
> unit: depends=none · scope=S7,S8 · files=docs/release-bump.md
- [ ] 2.1 Write `docs/release-bump.md`: the flow, GitHub App setup (name, installed on Homelab-Managment only, permissions Contents RW / Pull requests RW / Metadata R, no others), secrets `HOMELAB_BUMP_APP_ID` and `HOMELAB_BUMP_APP_KEY` per app repo, the repo setting `allow_auto_merge` on and the existing `main` ruleset left as is (list its four required checks), how to add a third app (caller job from design.md Contracts), red bump PR and behind-`main` bump PR recovery, R2 and R3 in one line each
- [ ] 2.2 `scripts/proof.sh --all` green

## 3. Life-Manager release.yml hookup
> unit: depends=1 · scope=S5 · files=../Life-Manager/.github/workflows/release.yml
- [ ] 3.1 In a worktree of `../Life-Manager` from `origin/main` (`flow/auto-version-bump`) append the `bump` job from the Contracts (`needs: publish`, `life_manager_version`, `life-manager01/vars.yml`), pinned to the local `ci` commit SHA from unit 1 with `# v1.1.0` comment (re-pinned in 4.5)
- [ ] 3.2 `actionlint .github/workflows/release.yml` clean; commit locally, record the hash here. Do not push

## 4. Human-only setup (Rue, never an agent)
> unit: depends=none · scope=S7 · files=none (GitHub UI and settings only; not built by an agent)
- [ ] 4.1 ⚠ irreversible (human-only) Create the GitHub App: name e.g. `homelab-bump`; permissions Contents: Read & write, Pull requests: Read & write, Metadata: Read-only; no webhook; install on `Rue-Asha/Homelab-Managment` only; generate a private key
- [ ] 4.2 ⚠ irreversible (human-only) Add repo secrets `HOMELAB_BUMP_APP_ID` and `HOMELAB_BUMP_APP_KEY` to `Rue-Asha/Life-Manager` (and later `Rue-Asha/Rues-Arcade`)
- [ ] 4.3 ⚠ (human-only) Homelab-Managment settings: General > Pull Requests > "Allow auto-merge" on. Leave the `main` ruleset unchanged (PR required, 0 reviews, required checks `proof`, `security-baseline / workflow-lint`, `security-baseline / secret-scan`, `security-baseline / dependency-review`, strict). Verify: `gh api repos/Rue-Asha/Homelab-Managment --jq .allow_auto_merge` prints `true`
- [ ] 4.4 ⚠ irreversible (human-only) Push the `ci` branch, open and merge the PR, tag `v1.1.0` (publish)
- [ ] 4.5 ⚠ (human-only) Re-pin the caller's `uses:` to the merged `ci` SHA, then push the Life-Manager branch, open and merge its PR

## 5. First real release (Rue)
> unit: depends=3,4 · scope=S4 · files=none (a real Life-Manager tag; not built by an agent)
- [ ] 5.1 ⚠ irreversible (human-only) Tag a Life-Manager release; watch `bump` open the PR, CI go green, auto-merge fire
- [ ] 5.2 Confirm R1: a `deploy` run for `03_SERVICES/life-manager.yml` started after the merge, and the smoke check passed
- [ ] 5.3 Re-run the `bump` job for the same tag: succeeds, no new PR (Done criterion 2)
- [ ] 5.4 `scripts/proof.sh --all` green on the final `flow/auto-version-bump`

## 6. Rues-Arcade release.yml hookup (BLOCKED on PR #23)
> unit: depends=1 · scope=S6 · files=../Rues-Arcade/.github/workflows/release.yml
- [ ] 6.1 BLOCKED: do not start until PR #23 (`feat/rues-arcade`) is merged to `main` (the `rues_arcade_version` file only exists there). Spike R5 is answered: its `verify.yml` has smoke check and rollback, so auto-merge stays
- [ ] 6.2 In a worktree of `../Rues-Arcade` from `origin/main` (`flow/auto-version-bump`) append the `bump` job (`rues_arcade_version`, `rues-arcade01/vars.yml`, `app: rues-arcade`), pinned to the real `ci` SHA from 4.4; `actionlint` clean; commit locally. Do not push
- [ ] 6.3 ⚠ (human-only) Push and merge the Rues-Arcade PR only after #23 is on `main`, secrets from 4.2 present; confirm with a real Rues-Arcade release (Done criterion 4)
