# agent-harness Specification

## Purpose

The coding agent working in this repo is governed by a harness of sensors,
gates, and backpressure: proof checks run deterministically, an agent commit is
blocked until they pass, and any command that changes real hosts needs a human.
Archived from `add-iac-harness`.

## Requirements
### Requirement: Proof sensors run the pre-commit checks deterministically

`scripts/proof.sh` SHALL be the single source of proof for this repo. Given a
set of changed files it SHALL run only the sensors relevant to them:

- any changed file under `terraform/` → `terraform fmt -check -recursive`,
  `terraform validate`, and `tflint`, run against `terraform/environments/homelab`
- any changed `.yml` file under `ansible/` → `ansible-lint` on those files,
  run from the repo root so `.ansible-lint` applies
- any changed file under `ansible/playbooks/` → `ansible-playbook --syntax-check`
  on that playbook

Each failing sensor SHALL print one line `INVARIANT_VIOLATION: <CODE>` followed
by the tool output, and the script SHALL exit non-zero if any sensor failed.
It SHALL support a staged mode (files from the git index) and a full mode (all
tracked files), and SHALL never contact a Proxmox node or a managed host.

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

### Requirement: Terraform state is never committed

The proof sensors SHALL fail when any `*.tfstate` or `*.tfstate.*` file is
staged, independent of `.gitignore`.

#### Scenario: State is force-added
- **WHEN** `terraform/environments/homelab/terraform.tfstate` is staged with `git add -f`
- **THEN** the output contains `INVARIANT_VIOLATION: TFSTATE_STAGED` and the exit code is non-zero

### Requirement: The agent cannot commit without proof

A `PreToolUse` hook on the Bash tool SHALL intercept every agent command that
runs `git commit` and run `scripts/proof.sh` before the commit executes. If any
sensor fails, the hook SHALL block the command with exit code 2 so the
violations are returned to the agent. Commands that do not run `git commit`
SHALL pass through without running any sensor.

When the command stages files in the same invocation (`git add … && git commit`
or `git commit -a`), the hook SHALL run the sensors in full mode, because the
index it can see does not yet contain those files.

#### Scenario: Commit with a lint failure
- **WHEN** the agent runs `git commit -m "…"` and a staged role file fails `ansible-lint`
- **THEN** the commit does not run and the agent receives the `INVARIANT_VIOLATION` lines

#### Scenario: Commit with clean changes
- **WHEN** the agent runs `git commit -m "…"` and every relevant sensor passes
- **THEN** the commit runs normally

#### Scenario: Unrelated command
- **WHEN** the agent runs `rg nginx_port ansible/`
- **THEN** the hook exits 0 without running any sensor

#### Scenario: Stage and commit in one command
- **WHEN** the agent runs `git add ansible/roles/nginx && git commit -m "…"`
- **THEN** the sensors run in full mode

### Requirement: Changes to real hosts need a human

A `PreToolUse` hook on the Bash tool SHALL return a permission decision of
`ask`, with a reason naming the command, for any agent command that runs
`terraform apply`, `terraform destroy`, or `ansible-playbook` without
`--check` or `--syntax-check`. Read-only commands such as `terraform plan`,
`terraform validate`, and `ansible-playbook --check` SHALL pass without a prompt.

#### Scenario: Agent tries to apply
- **WHEN** the agent runs `terraform -chdir=terraform/environments/homelab apply`
- **THEN** the user is asked to confirm before it runs

#### Scenario: Agent runs a playbook for real
- **WHEN** the agent runs `ansible-playbook ansible/playbooks/03_SERVICES/pihole.yml`
- **THEN** the user is asked to confirm before it runs

#### Scenario: Agent runs a check
- **WHEN** the agent runs `ansible-playbook ansible/playbooks/03_SERVICES/pihole.yml --check --diff`
- **THEN** the command runs without a prompt

#### Scenario: Agent plans
- **WHEN** the agent runs `terraform -chdir=terraform/environments/homelab plan`
- **THEN** the command runs without a prompt

### Requirement: Gates are wired in the repository

Both gates SHALL be registered in a checked-in `.claude/settings.json`, so any
clone of the repo gets them without per-machine setup.

#### Scenario: Fresh clone
- **WHEN** the repo is cloned and Claude Code is started at its root
- **THEN** both `PreToolUse` gates are active for Bash commands

### Requirement: Proof is available as an intent-level verb

A `/proof` slash command SHALL run `scripts/proof.sh` (staged mode by default,
full mode when asked) and report one pass/fail line per sensor that ran,
followed by the violation details for any failure.

#### Scenario: Running /proof with a failure
- **WHEN** the user runs `/proof` and `tflint` fails
- **THEN** the reply lists each sensor with pass or fail and shows the `tflint` output

