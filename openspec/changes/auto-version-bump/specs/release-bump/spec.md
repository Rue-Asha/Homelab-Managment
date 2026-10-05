## ADDED Requirements

### Requirement: A reusable workflow bumps a pinned version to a release tag

`Rue-Asha/ci` SHALL provide `.github/workflows/bump-pin.yml`, callable with `app`, `host_vars_path`, `variable`, `tag`, optionally `target_repo` (`owner/name`, default `Rue-Asha/Homelab-Managment`; the App token's owner and repository are derived from it) and the secrets `app_id` and `app_private_key`. It SHALL set `<variable>` to `<tag>` in `<host_vars_path>` of a checkout of Homelab-Managment, change nothing else in the file (the value alone is replaced: quoting and a trailing comment on the line stay), push branch `bump/<variable>-<tag>` and open a PR titled `chore(<app>): bump to <tag>`, whose commit message is the same conventional-commit line. The edit SHALL be made by `scripts/bump-pin.sh`.

#### Scenario: A new tag is bumped
- **WHEN** `life_manager_version: v0.2.0` is bumped to `v0.3.0`
- **THEN** the script prints `changed`, only that line differs, and the job pushes `bump/life_manager_version-v0.3.0` and opens a PR titled `chore(life-manager): bump to v0.3.0`
- **proof:** unit ("Scenario: A new tag is bumped"); manual (branch push and PR creation need a real release)

#### Scenario: The line has quotes, a comment or special characters
- **WHEN** the line is `<variable>: "v0.2.0"` or `<variable>: v0.2.0  # note`, or the tag contains `&` or `|`
- **THEN** only the value changes, quotes and comment are kept, the tag is written literally, and a line that already holds the tag in those forms prints `unchanged`
- **proof:** unit ("Scenario: The line has quotes, a comment or special characters"; "Scenario: The value already equals the tag")

#### Scenario: The variable line is missing
- **WHEN** the file has no `<variable>:` line
- **THEN** the script exits non-zero with a message naming the file and the variable, and the job fails
- **proof:** unit ("Scenario: The variable line is missing")

#### Scenario: The value already equals the tag
- **WHEN** the job is re-run for a tag the file already pins
- **THEN** the script prints `unchanged`, no branch or PR is created, and the job succeeds
- **proof:** unit ("Scenario: The value already equals the tag")

#### Scenario: Branch or PR for the tag already exists
- **WHEN** a PR for `bump/<variable>-<tag>` is merged, or open with auto-merge enabled
- **THEN** the job creates and enables nothing and succeeds
- **proof:** unit ("Scenario: Branch or PR for the tag already exists", stubbed `gh`); manual (a re-run of a real bump job)

#### Scenario: A previous run stopped before the PR or auto-merge
- **WHEN** `bump/<variable>-<tag>` exists without a PR (for example `gh pr create` failed after the push), or its open PR lacks auto-merge
- **THEN** a re-run opens the missing PR without pushing again and enables auto-merge, and succeeds
- **proof:** unit ("Scenario: A previous run stopped before the PR or auto-merge", stubbed `gh`); manual (needs a real failure)

#### Scenario: A pre-release tag is not bumped
- **WHEN** the tag is `v1.2.3-rc1`
- **THEN** the script prints `skipped`, the file is untouched, no PR is opened, and the job succeeds
- **proof:** unit ("Scenario: A pre-release tag is not bumped")

### Requirement: The bump PR is opened with a GitHub App token

The workflow SHALL create the branch and PR with an installation token of the GitHub App for Homelab-Managment, so that `ci.yml` runs on the PR. It SHALL NOT fall back to `GITHUB_TOKEN`.

#### Scenario: CI runs on the bump PR
- **WHEN** the bump PR is opened
- **THEN** the `proof` and `security-baseline` checks start on it
- **proof:** manual (needs the App and a real release)

#### Scenario: The App lacks access
- **WHEN** the token step fails because the App is not installed on Homelab-Managment or the secrets are wrong
- **THEN** the job fails with the token error and no PR is opened under any other identity
- **proof:** manual (needs a call with a wrong App id; actionlint covers that no `GITHUB_TOKEN` fallback is written)

### Requirement: A newer bump PR supersedes older open ones

After opening the PR for a tag, the workflow SHALL close every other open PR whose head branch starts with `bump/<variable>-`, with a comment naming the new PR.

#### Scenario: An older bump PR is still open
- **WHEN** `bump/life_manager_version-v0.3.0` is open and the job opens `bump/life_manager_version-v0.3.1`
- **THEN** the v0.3.0 PR is closed with a comment pointing at the v0.3.1 PR
- **proof:** unit ("Scenario: An older bump PR is still open", stubbed `gh`); manual (two real PRs)

#### Scenario: The older PR was already merged
- **WHEN** the previous bump PR for the variable is merged
- **THEN** nothing is closed and the job succeeds
- **proof:** manual (second real release)

### Requirement: A green bump PR merges itself and deploys

The workflow SHALL enable auto-merge on the PR with `gh pr merge --auto --squash`. The merge SHALL start `deploy.yml`, which deploys the service playbook for the changed host_vars file, unchanged.

#### Scenario: CI is green
- **WHEN** the bump PR's required checks pass
- **THEN** GitHub squash-merges it and a `deploy` run for the service playbook starts on `main`
- **proof:** manual (first real release; confirms R1)

#### Scenario: CI is red
- **WHEN** a required check fails on the bump PR
- **THEN** the PR stays open and no deploy runs
- **proof:** manual (needs a failing bump PR; GitHub behaviour)

#### Scenario: The smoke check fails after the merge
- **WHEN** the deployed release does not answer through nginx
- **THEN** the role's existing rollback applies, the deploy run is red, and the pin on `main` names a version the host does not run (accepted, R3)
- **proof:** manual (existing behaviour, covered by the continuous-deployment spec)

### Requirement: Life-Manager releases trigger the bump

Life-Manager's `release.yml` SHALL run a `bump` job after `publish` that calls the reusable workflow for `life_manager_version` in `ansible/inventory/host_vars/life-manager01/vars.yml`.

#### Scenario: A release is published
- **WHEN** `publish` succeeds for tag `v0.3.0`
- **THEN** the `bump` job runs with `tag: v0.3.0`
- **proof:** manual (needs a real tag); actionlint over `release.yml`

#### Scenario: Publish fails
- **WHEN** `publish` fails
- **THEN** the `bump` job does not run
- **proof:** manual (`needs: publish`, checked by reading `release.yml`; actionlint)

### Requirement: Rues-Arcade releases trigger the bump after PR #23

Rues-Arcade's `release.yml` SHALL call the reusable workflow for `rues_arcade_version` in `ansible/inventory/host_vars/rues-arcade01/vars.yml`. This is BLOCKED on PR #23 being merged and SHALL NOT be merged before it, and does not hold up the Life-Manager hookup.

#### Scenario: A release is published after #23
- **WHEN** `publish` succeeds for a Rues-Arcade tag and #23 is on `main`
- **THEN** the `bump` job opens a bump PR for `rues_arcade_version`, which merges and deploys like Life-Manager's
- **proof:** manual (needs a real tag after #23)

#### Scenario: The file is not on main yet
- **WHEN** the bump runs while `rues-arcade01/vars.yml` is missing on `main`
- **THEN** the script exits non-zero with `bump-pin: <file>: file not found` naming it, and the job fails
- **proof:** unit ("Scenario: The file is not on main yet"); the merge-order rule is manual

### Requirement: Auto-merge is enabled on Homelab-Managment

The repository setting `allow_auto_merge` SHALL be on. The existing `main` ruleset (PR required, no required reviews, required checks `proof`, `security-baseline / workflow-lint`, `security-baseline / secret-scan`, `security-baseline / dependency-review`) SHALL stay in force. Rue applies the setting by hand; `docs/release-bump.md` lists it exactly.

#### Scenario: Auto-merge can be enabled
- **WHEN** `gh api repos/Rue-Asha/Homelab-Managment --jq .allow_auto_merge` is run after Rue applied the setting
- **THEN** it prints `true`
- **proof:** manual (repo settings are applied by hand)

### Requirement: The release-bump flow is documented

`docs/release-bump.md` SHALL describe the flow, the GitHub App setup (permissions, secrets per app repo), the repo settings, how to add a new app, and what to do when a bump PR is red or behind `main`.

#### Scenario: Rue sets up a third app
- **WHEN** Rue reads `docs/release-bump.md` with a new app repo
- **THEN** it names the secrets to add, the caller job to paste and the host_vars variable to point it at, without needing further questions
- **proof:** manual (doc review at Gate 2)
