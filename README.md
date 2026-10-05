# Homelab-Managment

Terraform + Ansible repository for my Proxmox homelab. Nothing is set up by
hand: Terraform creates each guest through the Proxmox API, every service gets
its own lightweight LXC, and a playbook is the only way in.

> **Docs:** project write-up on the blog —
> [rue-asha.github.io/projects/homelab](https://rue-asha.github.io/projects/homelab/).
> This README only covers running the automation itself.

## What's here

| Service / role | Purpose |
|---|---|
| `nginx` | Host-level reverse proxy in front of each web service |
| `nodejs` | Runtime for the SvelteKit services below |
| `life_manager` | Deploys [Life-Manager](https://github.com/Rue-Asha/Life-Manager) |
| `rues_arcade` | Deploys [Rues-Arcade](https://github.com/Rue-Asha/Rues-Arcade) |
| `common` | Base host hardening shared by every guest |
| `guest_bootstrap` | First run on a fresh guest: `ansible` user + sudo |
| `proxmox_lxc_tun` | `/dev/net/tun` passthrough on the node (for a future Tailscale guest) |
| `github_runner` | Self-hosted GitHub Actions runner that deploys merges to `main` |
| `egress_firewall` | Default-drop outbound nftables firewall (on the runner) |

Provisioning (creating, resizing, destroying LXCs/VMs) is not an Ansible role —
it is `terraform/`, with the host catalogue in
`terraform/environments/homelab/hosts.auto.tfvars`.

Application services follow an **app-per-LXC, two-repo model**: this repo
configures the host and installs the runtime; the application code lives in
its own repo, whose CI builds and tests a release tarball; the host downloads
that exact artifact at a pinned tag (no Docker — `systemd` supervises the
process). See
`docs/party-games-webservice-architecture.md` for a worked example.

## Repo layout

Two peer layers in one repo: Terraform provisions the guests, Ansible
configures them. See `docs/terraform-ansible-split.md` for where the line runs.

```
terraform/                    # provisioning layer — Proxmox guest lifecycle
  environments/homelab/       #   the single root module: one node, one state
    hosts.auto.tfvars         #   the host catalogue
  modules/                    #   proxmox_lxc, proxmox_vm
ansible/                      # configuration layer — everything inside a guest
  ansible.cfg
  inventory/                  #   group_vars/host_vars (no vars in `hosts` itself)
  playbooks/
    00_OPERATIONAL/           #   ad-hoc / day-2 ops
    01_BASE_CONFIGURATION/    #   users, SSH, hardening
    02_SERVICES/              #   application install & config
  roles/                      #   standard Galaxy role structure
.ansible-lint                 # at the root so lint and the pre-commit hook find it
scripts/proof.sh              # every check; run by the git pre-commit hook and CI
scripts/deploy-targets.sh     # which 02_SERVICES playbooks a change deploys
.githooks/pre-commit          # commit gate, enabled by .envrc
ci/requirements.txt           # pinned ansible-core, ansible-lint, checkov for CI
docs/                         # architecture notes and implementation plans
openspec/                     # OpenSpec change proposals for larger pieces of work
```

The `NN_` prefix on playbook categories encodes the order a fresh host moves
through them. Provisioning is not a category: that step is `terraform apply`.

Run everything **from the repo root**: `.envrc` exports `ANSIBLE_CONFIG`, so
Ansible finds its config in `ansible/` without changing directory.

```sh
direnv allow                                          # once
terraform -chdir=terraform/environments/homelab apply
ansible-playbook ansible/playbooks/01_BASE_CONFIGURATION/bootstrap.yml -l life-manager01  # fresh guests only
ansible-playbook ansible/playbooks/02_SERVICES/life-manager.yml -l life-manager01
ansible-playbook ansible/playbooks/02_SERVICES/rues-arcade.yml -l rues-arcade01
```

Normally you don't run that last line yourself: **merging to `main` deploys.**
`.github/workflows/deploy.yml` runs the affected `02_SERVICES` playbooks on the
self-hosted runner `runner01`, and a service that fails its smoke check rolls
back to its previous release. Setup, key rotation and the manual fallback:
`docs/deploy-runner.md`.

Credentials live outside the repo: the PVE API token in
`~/.config/homelab/terraform.env` (loaded by direnv) and the ansible-vault
password in `~/.config/homelab/vault_pass`. Terraform state is local and
git-ignored — back it up with the control host. Full setup and day-2 commands:
`terraform/README.md`.

## Checks

```sh
scripts/proof.sh          # fmt, validate, tflint, checkov, ansible-lint, syntax-check, workflow/pin sensors — staged files only
scripts/proof.sh --all    # the same, whole repo
```

Each failing check prints `INVARIANT_VIOLATION: <CODE>`.

- **Commit gate** — `.githooks/pre-commit` runs `proof.sh` on every commit,
  from a terminal, neovim or Claude Code alike. `direnv allow` points
  `core.hooksPath` at it. `git commit --no-verify` skips it, but CI runs the
  same checks before anything merges.
- **CI** — `.github/workflows/ci.yml` runs `proof.sh --all` on every PR and
  push to `main`, plus the shared
  [`Rue-Asha/ci`](https://github.com/Rue-Asha/ci) security baseline (workflow
  lint, secret scan, dependency review). CI is the authority: `main` only
  merges with `proof` and every `security-baseline / …` check green. CI never
  reaches the homelab; only `deploy.yml` does, with credentials that live on
  the runner. The repo holds no GitHub secrets. Tool versions CI uses are pinned in
  `ci/requirements.txt` and the workflow; `pip install -r ci/requirements.txt`
  matches them locally.
- **Claude Code** — `.claude/settings.json` asks for confirmation before
  `terraform apply`/`destroy`, an `ansible-playbook` run without `--check`,
  and `gh pr merge` / `gh workflow run`, which deploy. `/proof` runs the sensors on
  demand.
