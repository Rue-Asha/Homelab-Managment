# github_runner

The self-hosted GitHub Actions runner that `.github/workflows/deploy.yml` runs
on. It runs deploys and nothing else.

- **User:** `github-runner`, no sudo, and the systemd unit sets
  `NoNewPrivileges`, so a job cannot become root and change the egress firewall.
- **Runner:** the pinned `github_runner_version`, downloaded with its checksum
  verified, registered with `--disableupdate` so the pin holds. Registered as a
  repository runner on `Rue-Asha/Homelab-Managment` only, label
  `homelab-deploy`.
- **Ansible:** a venv with the ansible-core pinned in `ci/requirements.txt`,
  first on the job `PATH`, so deploys run the version CI lints against.
- **Credentials:** a deploy key pair generated on the runner (the private half
  never leaves it), the Ansible vault password file, and a `known_hosts` built
  by scanning every `proxmox_guest` while this role runs. All three reach jobs
  through the runner's `.env`, which overrides `ansible.cfg`:

      ANSIBLE_PRIVATE_KEY_FILE, ANSIBLE_VAULT_PASSWORD_FILE,
      ANSIBLE_HOST_KEY_CHECKING=True, ANSIBLE_SSH_ARGS (UserKnownHostsFile)

  No GitHub secret is involved.

## Usage

Via `playbooks/01_BASE_CONFIGURATION/deploy_runner.yml`, by hand only — see
`docs/deploy-runner.md` for bootstrap, registration, key rotation and
re-scanning host keys.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `github_runner_registration_token` | `""` | One-time token; registration is skipped without it |
| `github_runner_repo_url` | this repo | Repository the runner serves |
| `github_runner_labels` | `[homelab-deploy]` | Labels on top of the default `self-hosted` ones |
| `github_runner_version` / `_sha256` | `2.337.0` / pinned | Runner release and its checksum |
| `github_runner_ansible_core` | from `ci/requirements.txt` | pip requirement for the deploy venv |
| `github_runner_ssh_targets` | `[]` | Guests whose host keys are pinned |
| `github_runner_vault_password_src` | `~/.config/homelab/vault_pass` | Controller-side vault password |
| `github_runner_public_key_dest` | `~/.config/homelab/deploy_ed25519.pub` | Where the public key is fetched to |
