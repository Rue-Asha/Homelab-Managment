## MODIFIED Requirements

### Requirement: CI never reaches the homelab and holds no secrets

No job in `.github/workflows/ci.yml` SHALL contact the Proxmox node or a
managed guest. No repository or environment secret SHALL be configured for any
workflow in this repo; the deploy workflow's credentials live on the
self-hosted runner. In CI, `terraform` SHALL be initialised with
`-backend=false`, and Ansible SHALL run with a vault password file that holds
no real password. `.github/workflows/deploy.yml` is the only workflow
permitted to reach the homelab.

#### Scenario: Workflow is inspected for secrets
- **WHEN** the repo's workflows and settings are inspected
- **THEN** no `secrets.*` reference other than `GITHUB_TOKEN` appears and the repository has no Actions or environment secrets

#### Scenario: CI runs on a pull request
- **WHEN** `ci.yml` runs for a PR
- **THEN** every one of its jobs runs on a GitHub-hosted runner

## ADDED Requirements

### Requirement: Self-hosted runners are unreachable from untrusted events

No job SHALL request a self-hosted runner in a workflow triggered by
`pull_request`, `pull_request_target`, `issues`, `issue_comment`, or any other
event a non-collaborator can cause. The proof SHALL fail a change that
introduces one. The repository SHALL require approval before running
workflows from fork PRs for all external contributors.

#### Scenario: A workflow mixes PR triggers with the runner
- **WHEN** a change adds `runs-on: [self-hosted, homelab-deploy]` to a workflow that has an `on: pull_request` trigger
- **THEN** the proof fails with a violation naming the workflow

#### Scenario: A returning outside contributor opens a PR
- **WHEN** someone who has had a PR merged before opens a PR from a fork
- **THEN** its workflows wait for maintainer approval before running
