# ci-pipeline Specification

## Purpose

GitHub Actions gives this repo an independent merge verdict: every pull request
and push to `main` runs `scripts/proof.sh --all` on a clean runner plus the
shared security baseline, without reaching the homelab or holding secrets, and
`main` cannot merge while a required check is red. Archived from `ci-homelab`.

## Requirements

### Requirement: CI runs the full proof on every change to main

`.github/workflows/ci.yml` SHALL run on `pull_request` targeting `main` and on
`push` to `main`. Its `proof` job SHALL run `scripts/proof.sh --all` on a
GitHub-hosted runner from a fresh checkout and SHALL fail when the script exits
non-zero. The job SHALL NOT define its own list of checks.

#### Scenario: A PR breaks Terraform formatting
- **WHEN** a PR changes a `.tf` file so that it is not `terraform fmt` clean
- **THEN** the `proof` check on the PR is red and its log contains `INVARIANT_VIOLATION: TERRAFORM_FMT_FAILED`

#### Scenario: A clean PR
- **WHEN** a PR changes only files that pass every sensor
- **THEN** the `proof` check on the PR is green

### Requirement: Missing tools fail CI

Every tool `proof.sh --all` invokes SHALL be installed in the job at a pinned
version. A `SENSOR_UNAVAILABLE` violation in CI SHALL fail the job.

#### Scenario: A tool is dropped from the job
- **WHEN** the step that installs `tflint` is removed
- **THEN** the `proof` check is red with `INVARIANT_VIOLATION: SENSOR_UNAVAILABLE (tflint)`

### Requirement: CI never reaches the homelab and holds no secrets

No job in this repo's workflows SHALL contact the Proxmox node or a managed
guest, and no repository or environment secret SHALL be configured for them.
`terraform` SHALL be initialised with `-backend=false`; Ansible SHALL run with a
vault password file that holds no real password.

#### Scenario: Workflow is inspected for secrets
- **WHEN** the repo's workflows and settings are inspected
- **THEN** no `secrets.*` reference other than `GITHUB_TOKEN` appears and the repository has no Actions secrets

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
