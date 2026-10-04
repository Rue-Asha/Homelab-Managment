## 1. checkov as a proof sensor

- [x] 1.1 Add the checkov sensor (`CHECKOV_FAILED`) to `scripts/proof.sh` for Terraform changes
- [x] 1.2 Run `scripts/proof.sh --all` locally; fix or inline-skip (with reason) every existing checkov finding
- [x] 1.3 Verify the "Terraform has a checkov finding" scenario by introducing a finding in a scratch edit and reverting it

## 2. One local commit gate for Rue and the agent

- [x] 2.1 Add `.githooks/pre-commit` (executable) that runs `scripts/proof.sh --staged`
- [x] 2.2 Set `core.hooksPath` to `.githooks` from `.envrc`
- [x] 2.3 Add `.claude/hooks/iac-no-verify-gate.sh`: block (exit 2) an agent `git commit` with `--no-verify` or `-n`, including bundled short flags like `-nm`
- [x] 2.4 In `.claude/settings.json`, replace `iac-proof-gate.sh` with `iac-no-verify-gate.sh`; delete `iac-proof-gate.sh`
- [x] 2.5 Verify the scenarios: lint failure blocks a terminal commit, `git add … && git commit` is caught, `--no-verify` from the agent is blocked, an unrelated command passes

## 3. Shared security baseline (`Rue-Asha/ci`)

- [x] 3.1 ⚠ Ask first: create the public repo `Rue-Asha/ci` on GitHub
- [x] 3.2 Write `.github/workflows/security-baseline.yml` (`workflow_call`): workflow-lint (actionlint + zizmor), secret-scan (gitleaks), dependency-review (PR only), each CLI pinned by version + checksum; fix the job names — they become required-check names
- [x] 3.3 Add a self-check workflow in `Rue-Asha/ci` that calls the baseline by relative path on PRs
- [x] 3.4 Add `.github/dependabot.yml` for `github-actions` in `Rue-Asha/ci`
- [x] 3.5 ⚠ Ask first: push and tag `v1.0.0` (publish)

## 4. CI workflow in this repo

- [x] 4.1 Add `ci/requirements.txt` with exact versions of ansible-core, ansible-lint, checkov
- [x] 4.2 Add `.github/workflows/ci.yml`: `proof` job (setup Python/Terraform/tflint, install collections, dummy vault password file, `scripts/proof.sh --all`) and a `security-baseline` job calling `Rue-Asha/ci@<sha> # v1.0.0`
- [x] 4.3 Add `.github/dependabot.yml` (`github-actions`, weekly)
- [x] 4.4 ⚠ Ask first: push a branch and open a PR; confirm both checks green
- [x] 4.5 Prove red: push a commit that breaks `terraform fmt`, confirm `TERRAFORM_FMT_FAILED` in the log, then revert

## 5. Adopt the baseline in Rue-Asha.github.io

- [x] 5.1 Add a `security-baseline` job to `publish.yml` (or a separate PR-triggered workflow) calling the pinned baseline
- [x] 5.2 Add `.github/dependabot.yml` there
- [x] 5.3 ⚠ Ask first: open the PR; confirm the site still publishes

## 6. Enforce

- [x] 6.1 ⚠ Ask first: create a `main` ruleset requiring `proof` and each `security-baseline / <job>` check by exact name, no admin bypass
- [x] 6.2 Verify: a PR with a red check cannot be merged
- [x] 6.3 Update `CLAUDE.md` "Before committing" and the README "Checks" section (checkov is a sensor; the commit gate is the git hook for everyone; CI is the authority) and run `update-docs`
