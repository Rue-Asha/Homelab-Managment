# ci-pipeline Specification

## Purpose

GitHub Actions gives this repo an independent merge verdict: every pull request
and push to `main` runs `scripts/proof.sh --all` on the isolated check runner
plus the shared security baseline, without reaching the homelab or holding
secrets, and
`main` cannot merge while a required check is red. Archived from `ci-homelab`.
## Requirements
### Requirement: CI runs the full proof on every change to main

`.github/workflows/ci.yml` SHALL run on `pull_request` targeting `main` and on
`push` to `main`. Its `proof` job SHALL run `scripts/proof.sh --all` on the
check runner (`runs-on: [self-hosted, homelab-check]`) from a fresh checkout and
SHALL fail when the script exits non-zero. The job SHALL NOT define its own list
of checks.

#### Scenario: A PR breaks Terraform formatting
- **WHEN** a PR changes a `.tf` file so that it is not `terraform fmt` clean
- **THEN** the `proof` check on the PR is red and its log contains `INVARIANT_VIOLATION: TERRAFORM_FMT_FAILED`
- **proof:** manual (needs a live PR on the check runner)

#### Scenario: A clean PR
- **WHEN** a PR changes only files that pass every sensor
- **THEN** the `proof` check on the PR is green
- **proof:** manual (needs a live PR on the check runner)

### Requirement: Missing tools fail CI

Every tool `proof.sh --all` invokes SHALL be installed on the check runner at a
pinned version. A `SENSOR_UNAVAILABLE` violation in CI SHALL fail the job.

#### Scenario: A tool is missing from the runner
- **WHEN** `tflint` is not installed on `check01`
- **THEN** the `proof` check is red with `INVARIANT_VIOLATION: SENSOR_UNAVAILABLE (tflint)`
- **proof:** manual (needs the live runner)

### Requirement: CI never reaches the homelab and holds no secrets

No job in `.github/workflows/ci.yml` SHALL contact the Proxmox node or a
managed guest. No repository or environment secret SHALL be configured for any
workflow in this repo; the deploy workflow's credentials live on the
deploy runner. In CI, `terraform` SHALL be initialised with `-backend=false`,
and Ansible SHALL run with a vault password file that holds no real password.
`.github/workflows/deploy.yml` is the only workflow permitted to reach the
homelab.

#### Scenario: Workflow is inspected for secrets
- **WHEN** the repo's workflows and settings are inspected
- **THEN** no `secrets.*` reference other than `GITHUB_TOKEN` appears and the repository has no Actions or environment secrets
- **proof:** manual (GitHub settings)

#### Scenario: CI runs on a pull request
- **WHEN** `ci.yml` runs for a PR
- **THEN** the `proof` job runs on the check runner and `security-baseline` runs on a GitHub-hosted runner
- **proof:** manual (needs a live PR)

### Requirement: Workflows follow the publishing controls

Every workflow in this repo SHALL declare `permissions` explicitly with
`contents: read` at the top level, SHALL pin every third-party action to a full
commit SHA with the release named in a trailing comment, and SHALL NOT trigger
on `pull_request_target`.

#### Scenario: An action is pinned to a tag
- **WHEN** a workflow references `actions/checkout@v7`
- **THEN** the security baseline's workflow lint fails the PR

### Requirement: CI is a required merge check

`main` SHALL be protected so that a PR cannot be merged unless the `proof`
check and every `security-baseline` job are green. The ruleset SHALL list each
check by its exact name, since rulesets do not match wildcards.

#### Scenario: Merge with a red check
- **WHEN** a PR's `proof` check is red
- **THEN** GitHub refuses the merge

### Requirement: Self-hosted runners are unreachable from untrusted events

A job SHALL NOT request a self-hosted runner in a workflow triggered by
`pull_request`, `pull_request_target`, `issues`, `issue_comment`, or any other
event a non-collaborator can cause, except one whose labels are exactly
`self-hosted` and `homelab-check`. A job carrying `homelab-deploy`, any other
self-hosted label, or a label expression SHALL be refused. The proof SHALL fail
a change that introduces one. The repository SHALL require approval before
running workflows from fork PRs for all external contributors.

#### Scenario: A workflow mixes PR triggers with the deploy runner
- **WHEN** a change adds `runs-on: [self-hosted, homelab-deploy]` to a workflow that has an `on: pull_request` trigger
- **THEN** the proof fails with a violation naming the workflow
- **proof:** unit ("Scenario: deploy label under a PR trigger" in `scripts/tests/workflow-triggers.sh`)

#### Scenario: A PR workflow uses the check runner
- **WHEN** a workflow with an `on: pull_request` trigger has a job with `runs-on: [self-hosted, homelab-check]`
- **THEN** the proof passes
- **proof:** unit ("Scenario: check label under a PR trigger" in `scripts/tests/workflow-triggers.sh`)

#### Scenario: Both labels on one job
- **WHEN** a PR-triggered job requests `[self-hosted, homelab-check, homelab-deploy]`
- **THEN** the proof fails
- **proof:** unit ("Scenario: mixed labels under a PR trigger" in `scripts/tests/workflow-triggers.sh`)

#### Scenario: A label comes from an expression
- **WHEN** a PR-triggered job has `runs-on: ${{ vars.RUNNER }}`
- **THEN** the proof fails
- **proof:** unit ("Scenario: expression under a PR trigger" in `scripts/tests/workflow-triggers.sh`)

#### Scenario: A returning outside contributor opens a PR
- **WHEN** someone who has had a PR merged before opens a PR from a fork
- **THEN** its workflows wait for maintainer approval before running
- **proof:** manual (GitHub settings)

