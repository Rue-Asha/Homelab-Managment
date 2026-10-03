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
| `pihole` | Network-wide DNS filtering |
| `tailscale` | Subnet router, remote access into the LAN |
| `nginx` | Host-level reverse proxy in front of each web service |
| `nodejs` | Runtime for the SvelteKit services below |
| `life_dashboard` | Deploys [Life-Managment-Dashboard](https://github.com/Rue-Asha/Life-Managment-Dashboard) |
| `partygames` | Deploys [Party-Games](https://github.com/Rue-Asha/Party-Games) |
| `retropie` | Retro-games box |
| `common` | Base host hardening shared by every guest |
| `guest_bootstrap` | First run on a fresh guest: `ansible` user + sudo |
| `proxmox_lxc_tun` | `/dev/net/tun` passthrough on the node for `tailscale01` |

Provisioning (creating, resizing, destroying LXCs/VMs) is not an Ansible role —
it is `terraform/`, with the host catalogue in
`terraform/environments/homelab/hosts.auto.tfvars`.

Application services follow an **app-per-LXC, two-repo model**: this repo
configures the host and installs the runtime; the application code lives in
its own repo and is checked out + built on the host at a pinned git tag (no
Docker, no CI required — `systemd` supervises the process). See
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
    02_BASE_CONFIGURATION/    #   users, SSH, hardening
    03_SERVICES/              #   application install & config
  roles/                      #   standard Galaxy role structure
.ansible-lint                 # at the root so lint and the pre-commit hook find it
scripts/proof.sh              # pre-commit checks, also run by the Claude Code commit gate
docs/                         # architecture notes and implementation plans
openspec/                     # OpenSpec change proposals for larger pieces of work
```

The `NN_` prefix on playbook categories encodes the order a fresh host moves
through them. `01_PROVISIONING` is gone — that step is now `terraform apply`.

Run everything **from the repo root**: `.envrc` exports `ANSIBLE_CONFIG`, so
Ansible finds its config in `ansible/` without changing directory.

```sh
direnv allow                                          # once
terraform -chdir=terraform/environments/homelab apply
ansible-playbook ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml -l pihole01  # fresh guests only
ansible-playbook ansible/playbooks/03_SERVICES/pihole.yml -l pihole01
```

Credentials live outside the repo: the PVE API token in
`~/.config/homelab/terraform.env` (loaded by direnv) and the ansible-vault
password in `~/.config/homelab/vault_pass`. Terraform state is local and
git-ignored — back it up with the control host. Full setup and day-2 commands:
`terraform/README.md`.

## Checks

```sh
scripts/proof.sh          # fmt, validate, tflint, ansible-lint, syntax-check — staged files only
scripts/proof.sh --all    # the same, whole repo
uvx checkov -d terraform --skip-path .terraform   # not part of proof.sh yet
```

Each failing check prints `INVARIANT_VIOLATION: <CODE>`. In Claude Code, two
hooks in `.claude/settings.json` use this as a harness: an agent `git commit`
is blocked until `proof.sh` passes, and `terraform apply`/`destroy` or an
`ansible-playbook` run without `--check` always asks for confirmation.
`/proof` runs the sensors on demand.
