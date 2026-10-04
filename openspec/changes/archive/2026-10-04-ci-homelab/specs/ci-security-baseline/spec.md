## ADDED Requirements

### Requirement: One shared security baseline

The repo `Rue-Asha/ci` SHALL provide `.github/workflows/security-baseline.yml`,
callable with `on: workflow_call`. It SHALL run:

- workflow lint over the caller's `.github/workflows/` (actionlint and zizmor)
- a secret scan of the caller's checkout (gitleaks)
- on `pull_request` events only, dependency review of the PR's dependency
  changes, failing on a newly introduced dependency with a known high or
  critical advisory

It SHALL need no secrets beyond `GITHUB_TOKEN` and SHALL request only
`contents: read` plus whatever single permission a step requires, declared on
that job.

#### Scenario: A secret is committed
- **WHEN** a caller's PR adds a file containing a private key
- **THEN** the baseline's secret-scan job is red

#### Scenario: A workflow uses pull_request_target
- **WHEN** a caller's PR adds a workflow triggered by `pull_request_target`
- **THEN** the baseline's workflow-lint job is red

#### Scenario: A vulnerable dependency is added
- **WHEN** a caller's PR adds an npm dependency with a known critical advisory
- **THEN** the baseline's dependency-review job is red

#### Scenario: Repo without a dependency manifest
- **WHEN** the baseline runs for a repo with no package manifest
- **THEN** dependency review passes without findings and the other jobs still run

### Requirement: Callers pin the baseline by SHA

Every caller SHALL reference the baseline as
`Rue-Asha/ci/.github/workflows/security-baseline.yml@<full commit SHA>`, never
a branch or tag, and a dependency-update bot SHALL propose bumps of that SHA.

#### Scenario: Baseline changes upstream
- **WHEN** a commit lands on `Rue-Asha/ci` `main`
- **THEN** no caller's CI behaviour changes until that caller merges a bump PR

### Requirement: The baseline lints itself

`Rue-Asha/ci` SHALL run its own baseline on every PR, calling it by relative
path.

#### Scenario: Breaking change to the baseline
- **WHEN** a PR to `Rue-Asha/ci` makes `security-baseline.yml` invalid
- **THEN** that PR's own check is red
