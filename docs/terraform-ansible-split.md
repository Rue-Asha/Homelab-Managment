# Terraform / Ansible split

Two tools, one boundary. This document is the reference for which one owns what,
and why the leftovers are where they are.

## The rule

> **Terraform** declares anything the Proxmox API owns: guest existence, vmid,
> hostname, CPU/memory/swap/disk, network interface and IP, boot behaviour,
> template/ISO reference (the homelab LXC template carries the `ansible` user and
template-baked public keys).
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
| `proxmox_lxc_bootstrap` — SSH key via `pct exec` | homelab LXC template (`scripts/build-lxc-template.sh`), converged by `guest_bootstrap` |
| `proxmox_lxc_bootstrap` — root password | **deleted**, see Secrets |
| `proxmox_lxc_bootstrap` — `ansible` user + sudo | homelab LXC template; `ansible/roles/guest_bootstrap` converges the keys via `02_BASE_CONFIGURATION/bootstrap.yml` |
| `ansible/roles/proxmox_lxc_tun` | **unchanged**, still Ansible — see below |
| `ansible/roles/common`, all of `03_SERVICES` | **unchanged** |

The app-per-LXC, two-repo, build-on-host service model is untouched. Nothing
about how services are deployed changed.

## Run order

A merge to `main` runs this in `deploy.yml` on `runner01`:

1. `plan` — saved as `<sha>.tfplan` on the runner; refused if it would delete or
   replace `runner01`.
2. `apply` — waits for approval in the `infrastructure` environment, applies the
   saved plan.
3. `deploy` — renders the inventory from state, then runs the affected
   `03_SERVICES` playbooks.

By hand, from the workstation (Terraform only runs on the runner):

```sh
scripts/fetch-inventory.sh                                # inventory from runner state
ansible-playbook ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml -l <host>
                                                          # converge guest keys + baseline
ansible-playbook ansible/playbooks/03_SERVICES/<service>.yml -l <host>
                                                          # the service
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

The role's `blockinfile` markers are comment lines in `<ctid>.conf`, and PVE
reports those as part of the container's `description`. `modules/proxmox_lxc`
therefore sets `lifecycle { ignore_changes = [description] }` — without it every
plan wants to strip the markers and the next tailscale run puts them back.

**Consequence to know about:** `terraform plan` will never notice the
passthrough is missing. If Terraform ever recreates `tailscale01`, it loses TUN
until the role runs again. Order after any recreate:

```sh
terraform apply
ansible-playbook ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml -l tailscale01
ansible-playbook ansible/playbooks/03_SERVICES/tailscale.yml -l tailscale01   # includes proxmox_lxc_tun
```

## How Ansible learns about hosts

Terraform exposes the inventory as the `ansible_inventory` output: host names,
addresses, group hierarchy, and `lxc_ctid`. `scripts/render-inventory.sh` writes
it to `ansible/inventory/00-terraform.yml` from state, on the runner, before
every deploy. The file is gitignored — committing it would need a push to
`main` after each apply, which re-triggers the deploy. State lives only on the
runner, so the workstation gets the inventory with `scripts/fetch-inventory.sh`.

The original design used the `ansible/ansible` Terraform provider plus the
`cloud.terraform` inventory plugin. That is not usable here: `cloud.terraform`
4.0.0, its latest release, calls `get_bin_path(..., required=True)`, and
ansible-core 2.21 removed that argument, so the plugin cannot parse the
inventory at all. Rendering turned out better anyway — no extra collection, no
extra provider, and the inventory is derived from the same tfvars change that caused it.

The group hierarchy is reproduced exactly (`<service>` →
`lxc_container_proxmox` / `vm_proxmox` → `proxmox_guest`), so every existing
file under `group_vars/` and `host_vars/` keeps resolving unchanged.

## Secrets

**Terraform needs exactly one kind of secret: a PVE API token.**

The workstation's belongs to a dedicated `terraform@pve` user with a custom PVE
role carrying only the privileges guest lifecycle requires — not `root@pam`, not
`PVEAdmin`. It lives in `~/.config/homelab/terraform.env` (mode `0600`, outside
the repo) and is loaded by `direnv`.

`runner01` applies with its own token, `terraform-deploy-node@pve!<id>`, written
to `~github-runner/.config/homelab/terraform.env` by `deploy_runner.yml` from
the workstation's `runner_terraform.env`. It uses the API only: no SSH to
`proxmox1` (the provider's `ssh {}` block is absent when `pve_ssh_enabled` is
false). The runner's firewall allows `proxmox1:8006` and nothing else there.

SSH keys are four separate pairs, so no single leak opens everything:

| Key | Opens |
|---|---|
| node key (`homelab_node_ed25519`) | `root@proxmox1` only |
| guest key (`homelab_guest_ed25519`) | `ansible@` every guest, never the node |
| deploy key (generated on `runner01`) | `ansible@` every guest except `runner01` |
| runner Terraform token | the PVE API, not SSH |

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

**State** is git-ignored and lives only on `runner01`, outside the job
workspace. It holds no credential, but it does record the full address and
container-ID plan. Backup is `scripts/fetch-state.sh` (a timestamped copy on the
workstation); the node has no vzdump job, so `runner01` is not otherwise
backed up. `imports.tf` stays
committed so a lost state file is one `terraform apply` to recover rather than
archaeology.

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

`checkov` ships no `bpg/proxmox` policies, so today it evaluates nothing here;
it stays in the gate for its secrets scan and for the cloud module on the
roadmap below.

## Roadmap

Follow-on work, ordered by value (design D11 of `add-terraform-provisioning`):

0. **HashiCorp Vault LXC** + migration of all ansible-vault secrets, with AWS
   KMS auto-unseal. Next in time, already decided.
1. **PVE users, roles, ACLs, API tokens as code** — makes the `terraform@pve`
   role itself reviewable.
2. **Proxmox firewall as code** — the LAN is a flat `/24` with no segmentation.
3. ~~**Template/ISO management**~~ Done for LXC: `scripts/build-lxc-template.sh`
   builds the homelab template on the node (not the provider's
   `download_file`), and existing guests never replan when it changes.
4. **Remote state with locking** (MinIO/S3-compatible LXC). Not done: state is
   local to `runner01`, serialised by the workflow's concurrency group and
   backed up by vzdump.
5. **Policy-as-code**: OPA/Conftest rules for homelab policy on top of checkov.
6. **Tailscale provider** — tailnet ACLs, auth keys, and the two manual
   admin-console steps as code.
7. **A real cloud module** (AWS/Azure free tier), deployed via OIDC and scanned
   by the same gate.
8. **Packer images** — only if the deploy model moves from converge-in-place to
   rebuild.
