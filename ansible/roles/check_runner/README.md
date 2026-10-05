# check_runner

The self-hosted GitHub Actions runner that `.github/workflows/ci.yml` runs
`scripts/proof.sh --all` on. It holds nothing and reaches nothing in the
homelab; it is the PR-facing counterpart to `github_runner`.

- **User:** `check-runner`, no sudo, and the systemd unit sets
  `NoNewPrivileges`, so a job cannot become root and change the egress firewall.
- **Runner:** the pinned `check_runner_version`, checksum-verified, registered
  with `--disableupdate`. Repository runner on `Rue-Asha/Homelab-Managment`
  only, label `homelab-check`. Persistent, not ephemeral: an ephemeral runner
  needs a registration credential on the box.
- **Toolchain:** Terraform and tflint in `/usr/local/bin`, ansible-core,
  ansible-lint and checkov in a root-owned venv built from `ci/requirements.txt`
  and first on the job `PATH`. A job can run them, not replace them.
- **Workspace:** a root-owned job-started hook empties the checkout directory
  before every job.
- **Credentials:** none. No deploy key, vault password, PVE token or secret.
  The role does not reference any of those variables.
- **Network:** the `egress_firewall` role with no SSH or API targets (see
  `group_vars/check_runner`): DNS and TCP 80/443 to non-private addresses.

## Usage

Via `playbooks/01_BASE_CONFIGURATION/check_runner.yml`, by hand only. See
`docs/check-runner.md`.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `check_runner_registration_token` | `""` | One-time token; registration is skipped without it |
| `check_runner_repo_url` | this repo | Repository the runner serves |
| `check_runner_labels` | `[homelab-check]` | Labels on top of the default `self-hosted` ones |
| `check_runner_version` / `_sha256` | `2.337.0` / pinned | Runner release and its checksum |
| `check_runner_terraform_version` / `_sha256` | `1.15.9` / pinned | Terraform release |
| `check_runner_tflint_version` / `_sha256` | `0.64.0` / pinned | tflint release |
| `check_runner_python_requirements` | from `ci/requirements.txt` | pip requirements for the venv |
