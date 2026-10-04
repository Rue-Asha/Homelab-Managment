## RENAMED Requirements

- FROM: `### Requirement: The agent cannot commit without proof`
- TO: `### Requirement: Every commit runs proof`

## MODIFIED Requirements

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
- **WHEN** the agent runs `ansible-playbook ansible/playbooks/03_SERVICES/pihole.yml`
- **THEN** the user is asked to confirm before it runs

#### Scenario: Agent runs a check
- **WHEN** the agent runs `ansible-playbook ansible/playbooks/03_SERVICES/pihole.yml --check --diff`
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
