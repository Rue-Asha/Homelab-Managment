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

- **No update path.** `ansible/roles/proxmox_lxc/tasks/create.yml` was gated on
  `when: not lxc_exists`, so changing `lxc_memory` on an existing host silently
  did nothing.
- **No teardown path.** Nothing implemented `state: absent`. Removing a host
  from `ansible/inventory/hosts` left the container running forever.
- **Hand-rolled idempotency.** Each role reimplemented "does it exist / is there
  free space" in `preflight.yml`, which a state file gives for free.

## What moved where

| Before | After |
|---|---|
| `ansible/roles/proxmox_lxc` | `terraform/modules/proxmox_lxc` |
| `ansible/roles/proxmox_vm_template`, `ansible/roles/proxmox_vm_iso` | `terraform/modules/proxmox_vm` |
| `ansible/playbooks/01_PROVISIONING/*` | `terraform apply` |
| `ansible/inventory/hosts` | `terraform/environments/homelab/hosts.auto.tfvars`, rendered into `ansible/inventory/00-terraform.yml` |
| `group_vars/{lxc_container_proxmox,vm_proxmox}.yml` | root-module variables |
| `proxmox_lxc_bootstrap` — SSH key via `pct exec` | Terraform `initialization.user_account.keys` |
| `proxmox_lxc_bootstrap` — root password | **deleted**, see Secrets |
| `proxmox_lxc_bootstrap` — `ansible` user + sudo | `ansible/roles/guest_bootstrap`, via `02_BASE_CONFIGURATION/bootstrap.yml` |
| `ansible/roles/proxmox_lxc_tun` | **unchanged**, still Ansible — see below |
| `ansible/roles/common`, all of `03_SERVICES` | **unchanged** |

The app-per-LXC, two-repo, build-on-host service model is untouched. Nothing
about how services are deployed changed.

## Run order

```sh
terraform -chdir=terraform/environments/homelab apply     # 1. infrastructure
ansible-playbook ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml -l <host>
                                                          # 2. ansible user + baseline
ansible-playbook ansible/playbooks/03_SERVICES/<service>.yml -l <host>
                                                          # 3. the service
```

For `tailscale01` there is an extra step between 2 and 3 — see the next section.

## The one thing Terraform cannot express

`ansible/roles/proxmox_lxc_tun` writes raw lines into `/etc/pve/lxc/<ctid>.conf` to pass
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
ansible-playbook ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml -l tailscale01
ansible-playbook ansible/playbooks/03_SERVICES/tailscale.yml -l tailscale01   # includes proxmox_lxc_tun
```

## How Ansible learns about hosts

Terraform renders `ansible/inventory/00-terraform.yml` on every apply: host
names, addresses, group hierarchy, and `lxc_ctid`. It is committed and marked
generated — `local_file` compares content on every plan, so a hand-edit or a
stale checkout surfaces as drift instead of being silently tolerated.

The original design used the `ansible/ansible` Terraform provider plus the
`cloud.terraform` inventory plugin. That is not usable here: `cloud.terraform`
4.0.0, its latest release, calls `get_bin_path(..., required=True)`, and
ansible-core 2.21 removed that argument, so the plugin cannot parse the
inventory at all. Rendering turned out better anyway — no extra collection, no
extra provider, no dependency on readable Terraform state at inventory time,
and the inventory shows up in diffs next to the tfvars change that caused it.

The group hierarchy is reproduced exactly (`<service>` →
`lxc_container_proxmox` / `vm_proxmox` → `proxmox_guest`), so every existing
file under `group_vars/` and `host_vars/` keeps resolving unchanged.

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
