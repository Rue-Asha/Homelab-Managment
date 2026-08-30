# Terraform / Ansible split

Two tools, one boundary. This document is the reference for which one owns what,
and why the leftovers are where they are.

## The rule

> **Terraform** declares anything the Proxmox API owns: guest existence, vmid,
> hostname, CPU/memory/swap/disk, network interface and IP, boot behaviour,
> template/ISO reference, and the SSH key seeded at creation.
>
> **Ansible** declares anything inside the guest: users, sudo, SSH hardening,
> packages, runtimes, services, application releases.
>
> Terraform `provisioner` / `remote-exec` / `local-exec` blocks are **banned**.
> They are one-shot, not idempotent, and invisible to `plan`. Configuration
> after boot is always an Ansible run.

## Why Terraform at all

The Ansible provisioning it replaced had no state, and therefore no
desired-state model. Three consequences, all visible in the code it removed:

- **No update path.** `roles/proxmox_lxc/tasks/create.yml` was gated on
  `when: not lxc_exists`, so changing `lxc_memory` on an existing host silently
  did nothing.
- **No teardown path.** Nothing implemented `state: absent`. Removing a host
  from `inventory/hosts` left the container running forever.
- **Hand-rolled idempotency.** Each role reimplemented "does it exist / is there
  free space" in `preflight.yml`, which a state file gives for free.

## What moved where

| Before | After |
|---|---|
| `roles/proxmox_lxc` | `terraform/modules/proxmox_lxc` |
| `roles/proxmox_vm_template`, `roles/proxmox_vm_iso` | `terraform/modules/proxmox_vm` |
| `playbooks/01_PROVISIONING/*` | `terraform apply` |
| `inventory/hosts` | `terraform/environments/homelab/hosts.auto.tfvars` |
| `group_vars/{lxc_container_proxmox,vm_proxmox}.yml` | root-module variables |
| `proxmox_lxc_bootstrap` — SSH key via `pct exec` | Terraform `initialization.user_account.keys` |
| `proxmox_lxc_bootstrap` — root password | **deleted**, see Secrets |
| `proxmox_lxc_bootstrap` — `ansible` user + sudo | `roles/guest_bootstrap`, via `02_BASE_CONFIGURATION/bootstrap.yml` |
| `roles/proxmox_lxc_tun` | **unchanged**, still Ansible — see below |
| `roles/common`, all of `03_SERVICES` | **unchanged** |

The app-per-LXC, two-repo, build-on-host service model is untouched. Nothing
about how services are deployed changed.

## Run order

```sh
terraform -chdir=terraform/environments/homelab apply     # 1. infrastructure
ansible-playbook playbooks/02_BASE_CONFIGURATION/bootstrap.yml -l <host>
                                                          # 2. ansible user + baseline
ansible-playbook playbooks/03_SERVICES/<service>.yml -l <host>
                                                          # 3. the service
```

For `tailscale01` there is an extra step between 2 and 3 — see the next section.

## The one thing Terraform cannot express

`roles/proxmox_lxc_tun` writes raw lines into `/etc/pve/lxc/<ctid>.conf` to pass
`/dev/net/tun` into the unprivileged container Tailscale runs in:

```
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

The `bpg/proxmox` provider models container config as typed attributes and has
no escape hatch for arbitrary `lxc.*` keys. This is a genuine provider gap, not
a stylistic preference, so the role stays — a host-level Ansible concern
delegated to the Proxmox node, deliberately outside the `tailscale` app role.

**Consequence to know about:** `terraform plan` will never notice the
passthrough is missing. If Terraform ever recreates `tailscale01`, it loses TUN
until the role runs again. Order after any recreate:

```sh
terraform apply
ansible-playbook playbooks/02_BASE_CONFIGURATION/bootstrap.yml -l tailscale01
ansible-playbook playbooks/03_SERVICES/tailscale.yml -l tailscale01   # includes proxmox_lxc_tun
```

## Secrets

**Terraform needs exactly one secret: the PVE API token.**

It belongs to a dedicated `terraform@pve` user with a custom PVE role carrying
only the privileges guest lifecycle requires — not `root@pam`, not `PVEAdmin`.
It lives in `~/.config/homelab/terraform.env` (mode `0600`, outside the repo)
and is loaded by `direnv`.

**That token is the bootstrap credential and stays outside Vault permanently.**
Vault runs in an LXC that Terraform provisions using this token; storing it in
Vault would make the system unbootstrappable. Every secret manager has exactly
one credential outside itself — this is the standard structure, not a
concession.

**Guest root passwords were deleted, not migrated.** `lxc_password` and
`vm_ci_password` solved no problem that exists here: `pct enter <ctid>` gives
passwordless root from the node unconditionally, and every guest is
key-authenticated. Keeping them would have meant managing and rotating three
never-used secrets and permanently marking the state file as holding
credentials. `pct enter` is the console fallback.

**State** is git-ignored and backed up with the control host. It holds no
credential, but it does record the full address and container-ID plan.
`imports.tf` stays committed so a lost state file is one `terraform apply` to
recover rather than archaeology.

Application secrets — Pi-hole password, the Proton ICS URL, the Tailscale
pre-auth key, both git deploy keys — remain Ansible's, and move to a self-hosted
HashiCorp Vault in a follow-up change. Nothing about that changes the boundary
above: they are guest-side configuration, so they belong to Ansible either way.

## Conventions

Terraform follows standard HashiCorp style, not the Ansible rules in
`.claude/CLAUDE.md` — `terraform fmt`, snake_case, and one
`main.tf` / `variables.tf` / `outputs.tf` / `versions.tf` per module.

Two project-specific rules worth stating:

- **`for_each` over a hostname-keyed map, never `count`.** With `count`,
  deleting a host renumbers every index after it and Terraform proposes
  destroying and recreating unrelated containers.
- **vmid and IP are independent declarations.** The pre-Terraform inventory
  derived the container ID from the fourth octet of the address, which meant a
  host could not be re-addressed without changing its container ID.

Before committing anything under `terraform/`:

```sh
terraform fmt -check -recursive
terraform validate
tflint
checkov -d .
```
