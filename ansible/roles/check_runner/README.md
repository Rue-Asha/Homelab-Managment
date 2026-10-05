# check_runner

The shared check host: self-hosted GitHub Actions runners that run each listed
repo's PR checks (`scripts/proof.sh --all` here). It holds nothing and reaches
nothing in the homelab; it is the PR-facing counterpart to `github_runner`.

- **Instances:** one per entry in `check_runner_repos`, each under its own user
  `check-runner-<slug>` (home `0700`, no sudo) and unit
  `check-runner-<slug>.service` with `NoNewPrivileges`, so a job can neither
  become root and change the egress firewall nor read another repo's runner.
- **Runner:** the pinned `check_runner_version`, checksum-verified, registered
  with `--disableupdate` as a repository runner, label `homelab-check`.
  Persistent, not ephemeral: an ephemeral runner needs a registration
  credential on the box. Tokens are minted by `gh` on the controller and
  never stored; the play first asserts each repo's fork-PR approval policy.
- **Toolchain:** Terraform and tflint in `/usr/local/bin`, ansible-core,
  ansible-lint and checkov in a root-owned venv built from `ci/requirements.txt`
  and first on the job `PATH`. A job can run them, not replace them.
  The apt list `check_runner_browser_packages` covers headless Chromium.
- **Workspace:** a per-instance root-owned job-started hook empties the
  checkout directory before every job.
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
| `check_runner_repos` | `[]` | `{repo: owner/name}` entries, one runner instance each |
| `check_runner_labels` | `[homelab-check]` | Labels on top of the default `self-hosted` ones |
| `check_runner_version` / `_sha256` | `2.337.0` / pinned | Runner release and its checksum |
| `check_runner_terraform_version` / `_sha256` | `1.15.9` / pinned | Terraform release |
| `check_runner_tflint_version` / `_sha256` | `0.64.0` / pinned | tflint release |
| `check_runner_python_requirements` | from `ci/requirements.txt` | pip requirements for the venv |
| `check_runner_browser_packages` | Debian 13 Chromium libraries | apt packages so jobs never need `--with-deps` |
| `check_runner_port_base` | `4173` | First `PORT` handed to jobs; instance N gets base+N so concurrent e2e runs don't collide |
