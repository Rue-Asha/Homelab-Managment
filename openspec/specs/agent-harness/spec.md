# agent-harness Specification

## Purpose

The coding agent working in this repo is governed by a harness of sensors,
gates, and backpressure: proof checks run deterministically, a git pre-commit
hook blocks every commit until they pass, CI is the authority behind that
hook, and any command that changes real hosts — including a merge or dispatch
that deploys — needs a human. Archived from `add-iac-harness`; the commit gate
moved into git with `ci-homelab`, and `trim-agent-gates` dropped the
no-verify gate.

## Requirements
### Requirement: Proof sensors run the pre-commit checks deterministically

`scripts/proof.sh` SHALL be the single source of proof for this repo. Given a
set of changed files it SHALL run only the sensors relevant to them:

- any changed file under `terraform/` → `terraform fmt -check -recursive`,
  `terraform validate`, `tflint`, and `checkov`, run against `terraform/environments/homelab`
- any changed `.yml` file under `ansible/` → `ansible-lint` on those files,
  run from the repo root so `.ansible-lint` applies
- any changed file under `ansible/playbooks/` → `ansible-playbook --syntax-check`
  on that playbook

Each failing sensor SHALL print one line `INVARIANT_VIOLATION: <CODE>` followed
by the tool output, and the script SHALL exit non-zero if any sensor failed.
It SHALL support a staged mode (files from the git index) and a full mode (all
tracked files), and SHALL never contact a Proxmox node or a managed host.
The full mode is the entry point CI calls; there is no separate CI check list.

#### Scenario: Terraform formatting is broken
- **WHEN** a staged file under `terraform/` is not `terraform fmt` clean and `scripts/proof.sh --staged` runs
- **THEN** the output contains `INVARIANT_VIOLATION: TERRAFORM_FMT_FAILED` and the exit code is non-zero

#### Scenario: Only Ansible changed
- **WHEN** the only staged file is `ansible/roles/nginx/tasks/configure.yml`
- **THEN** `ansible-lint` runs on that file and no Terraform sensor runs

#### Scenario: A playbook no longer parses
- **WHEN** a staged playbook under `ansible/playbooks/` has a syntax error
- **THEN** the output contains `INVARIANT_VIOLATION: ANSIBLE_SYNTAX_CHECK_FAILED` naming that playbook

#### Scenario: Nothing relevant changed
- **WHEN** the only staged file is under `docs/` or `openspec/`
- **THEN** no sensor runs and the exit code is zero

#### Scenario: A sensor tool is missing
- **WHEN** a relevant sensor's binary is not on `PATH`
- **THEN** the output contains `INVARIANT_VIOLATION: SENSOR_UNAVAILABLE (<tool>)` and the exit code is non-zero, rather than the sensor being skipped silently

#### Scenario: Terraform has a checkov finding
- **WHEN** a staged file under `terraform/` introduces a checkov finding that is neither fixed nor skipped with an inline reason
- **THEN** the output contains `INVARIANT_VIOLATION: CHECKOV_FAILED` and the exit code is non-zero

### Requirement: Terraform state is never committed

The proof sensors SHALL fail when any `*.tfstate` or `*.tfstate.*` file is
staged, independent of `.gitignore`.

#### Scenario: State is force-added
- **WHEN** `terraform/environments/homelab/terraform.tfstate` is staged with `git add -f`
- **THEN** the output contains `INVARIANT_VIOLATION: TFSTATE_STAGED` and the exit code is non-zero

### Requirement: Changes to real hosts need a human

A `PreToolUse` hook on the Bash tool SHALL return a permission decision of
`ask`, with a reason naming the command, for any agent command that runs
`terraform apply`, `terraform destroy`, or `ansible-playbook` without
`--check` or `--syntax-check`. Because merging to `main` and dispatching a
workflow deploy, it SHALL also ask for `gh pr merge`, `gh workflow run`, and
any `gh api` call whose path ends in `/merge` or `/dispatches`. Read-only
commands such as `terraform plan`, `terraform validate`,
`ansible-playbook --check`, and `gh pr view` SHALL pass without a prompt.

#### Scenario: Agent tries to apply
- **WHEN** the agent runs `terraform -chdir=terraform/environments/homelab apply`
- **THEN** the user is asked to confirm before it runs

#### Scenario: Agent runs a playbook for real
- **WHEN** the agent runs `ansible-playbook ansible/playbooks/02_SERVICES/pihole.yml`
- **THEN** the user is asked to confirm before it runs

#### Scenario: Agent runs a check
- **WHEN** the agent runs `ansible-playbook ansible/playbooks/02_SERVICES/pihole.yml --check --diff`
- **THEN** the command runs without a prompt

#### Scenario: Agent plans
- **WHEN** the agent runs `terraform -chdir=terraform/environments/homelab plan`
- **THEN** the command runs without a prompt

#### Scenario: Agent merges a PR
- **WHEN** the agent runs `gh pr merge 12 --merge`
- **THEN** the user is asked to confirm before it runs

#### Scenario: Agent dispatches a deploy
- **WHEN** the agent runs `gh workflow run deploy.yml -f playbook=life-manager`
- **THEN** the user is asked to confirm before it runs

#### Scenario: Agent reads a PR
- **WHEN** the agent runs `gh pr view 12`
- **THEN** the command runs without a prompt

### Requirement: Gates are wired in the repository

The real-host gate SHALL be registered in a checked-in `.claude/settings.json`.
The git `pre-commit` hook SHALL live in the tracked `.githooks/` directory, and
`.envrc` SHALL set `core.hooksPath` to it, so a clone gets every gate without
per-machine setup beyond `direnv allow`. There SHALL be no Claude Code hook
that runs `scripts/proof.sh` on commit.

#### Scenario: Fresh clone
- **WHEN** the repo is cloned, `direnv allow` is run, and Claude Code is started at its root
- **THEN** the real-host `PreToolUse` gate is active for Bash commands and `git config core.hooksPath` is `.githooks`

### Requirement: Proof is available as an intent-level verb

A `/proof` slash command SHALL run `scripts/proof.sh` (staged mode by default,
full mode when asked) and report one pass/fail line per sensor that ran,
followed by the violation details for any failure.

#### Scenario: Running /proof with a failure
- **WHEN** the user runs `/proof` and `tflint` fails
- **THEN** the reply lists each sensor with pass or fail and shows the `tflint` output

### Requirement: Every commit runs proof

A tracked git `pre-commit` hook, `.githooks/pre-commit`, SHALL run
`scripts/proof.sh --staged` before every commit — whoever makes it, Rue or the
agent — and SHALL abort the commit when the script exits non-zero, printing the
violations. Because git runs the hook after staging, files staged in the same
invocation (`git add … && git commit`, `git commit -a`) SHALL be covered by
staged mode without a full-mode fallback.

The hook is local feedback, not the authority: a commit made with
`--no-verify` SHALL still be unable to reach `main`, because CI runs
`scripts/proof.sh --all` as a required, up-to-date check.

#### Scenario: Commit with a lint failure
- **WHEN** the agent runs `git commit -m "…"` and a staged role file fails `ansible-lint`
- **THEN** the commit does not run and the agent receives the `INVARIANT_VIOLATION` lines

#### Scenario: Rue commits from the terminal
- **WHEN** Rue runs `git commit` outside Claude Code and a staged `.tf` file is not `terraform fmt` clean
- **THEN** the commit is aborted and the output contains `INVARIANT_VIOLATION: TERRAFORM_FMT_FAILED`

#### Scenario: Commit with clean changes
- **WHEN** a commit is made and every relevant sensor passes
- **THEN** the commit runs normally

#### Scenario: Stage and commit in one command
- **WHEN** `git add ansible/roles/nginx && git commit -m "…"` runs and a file under `ansible/roles/nginx` fails `ansible-lint`
- **THEN** the commit is aborted

