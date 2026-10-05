# Terraform — Proxmox guest lifecycle

Terraform owns everything the Proxmox API owns: guest existence, vmid,
hostname, CPU/memory/swap/disk, network interface and IP, boot behaviour, the
template reference, and the SSH key seeded at creation.

Ansible owns everything *inside* the guest: users, sudo, SSH hardening,
packages, runtimes, services, application releases.

**Terraform `provisioner` / `remote-exec` / `local-exec` blocks are banned here.**
They are one-shot, not idempotent, and invisible to `plan`. Configuration after
boot is always an Ansible run.

## Layout

This tree is the provisioning layer; `../ansible/` is the configuration layer.
Both sit at the repo root as peers.

```
environments/homelab/     the only root module — one node, one state
  hosts.auto.tfvars       the host catalogue (replaced ansible/inventory/hosts)
  imports.tf              commented-out state-loss recovery path
  ansible.tf              inventory metadata consumed by Ansible
modules/proxmox_lxc/      one container
modules/proxmox_vm/       one VM, clone-from-template or ISO shell
```

Run Terraform from the repo root with `-chdir`, so the Ansible commands that
follow keep resolving their relative paths:

```sh
terraform -chdir=terraform/environments/homelab plan
```

## Credentials

One secret, supplied through the environment, never committed:

```sh
install -d -m 0700 ~/.config/homelab
install -m 0600 /dev/null ~/.config/homelab/terraform.env
cat > ~/.config/homelab/terraform.env <<'EOF'
export PROXMOX_VE_ENDPOINT='https://192.168.0.22:8006/'
export PROXMOX_VE_API_TOKEN='terraform@pve!<token-id>=<uuid>'
EOF
```

`.envrc` loads it via `direnv` on entering `environments/homelab/`; run
`direnv allow` once.

The token belongs to a dedicated `terraform@pve` user with a **custom PVE role**
carrying only the privileges these operations need — not `root@pam`, not
`PVEAdmin`.

**This token is the bootstrap credential for the homelab and stays outside
Vault permanently.** Vault runs in an LXC that Terraform provisions using this
token; putting it in Vault would make the system unbootstrappable. Every secret
manager has exactly one credential outside itself.

Guests have **no root password**. `pct enter <ctid>` from the node gives
passwordless root, so a container root password protects nothing while still
being a secret to store and rotate. Access is SSH-key-only.

## State

Local, git-ignored, and part of whatever backs up this control host. It holds no
credential, but it does record the complete address and container-ID plan.

Losing it is recoverable — `imports.tf` stays in the repo precisely so
re-adoption is one `terraform apply` rather than archaeology.

## First run (rebuild)

The four pre-existing containers are **destroyed and recreated**, not imported.
That was a deliberate choice: importing proves only that Terraform can describe
what already exists, never that it can build it, and every future host takes the
create path. See design D9 in the OpenSpec change for the full reasoning.

Consequences to know before starting:

- **There is no rollback.** The old containers must be gone before Terraform can
  create guests with the same vmids. Existing guest data is discarded by
  decision — the SQLite databases and uploaded images are not preserved.
- **The LAN loses DNS** while `pihole01` is down, if the router points at it.
  `pihole01` is declared again (see `docs/pihole.md`); set a fallback resolver
  on the router first, or rebuild it last.

```sh
terraform -chdir=terraform/environments/homelab init    # commit .terraform.lock.hcl
terraform -chdir=terraform/environments/homelab plan    # expect N creates, 0 destroys
```

Read the plan in full before applying — that habit is the only safety net left.
Then, on the node, `pct stop <ctid> && pct destroy <ctid>` for each old guest,
and:

```sh
terraform -chdir=terraform/environments/homelab apply
terraform -chdir=terraform/environments/homelab plan    # must say "No changes"

ansible-playbook ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml
ansible-playbook ansible/playbooks/03_SERVICES/<service>.yml -l <host>
```

Before trusting it, run the API preflight: confirm the LXC template exists on
`local`, that `local-lvm` has room, and that the declared sizing matches what
you actually want. That check already caught `pihole01` being declared at
1024 MiB / 8 GiB when the live container ran at 512 / 4.

## Day-2

```sh
terraform plan                  # drift detection; read it before every apply
terraform apply                 # converge
terraform apply -target=...     # single host, when you must
terraform output lxc_hosts      # hostname -> vmid + address
```

Adding a host: add an entry to `hosts.auto.tfvars`, `apply`, then run the
Ansible baseline and the service playbook.

Removing a host: delete its entry and `apply`. There is deliberately no
`prevent_destroy` — it cannot be driven by a variable, so it would apply to
throwaway hosts too and turn every intended removal into a two-step edit. The
protection is reading the plan.

## What Terraform does *not* do here

`ansible/roles/proxmox_lxc_tun` writes raw `lxc.mount.entry` lines into
`/etc/pve/lxc/<ctid>.conf` for `/dev/net/tun` passthrough on `tailscale01`. The
provider models container config as typed attributes with no escape hatch for
arbitrary `lxc.*` keys, so this stays a host-level Ansible role delegated to the
node.

Its `blockinfile` markers show up in the container's `description`, which is
why `modules/proxmox_lxc` ignores changes to `description` after create.

**Consequence:** `terraform plan` will never notice that passthrough is missing,
and a container recreated by Terraform loses TUN until the role runs again. For
`tailscale01` the order after any recreate is: `terraform apply` → baseline →
`proxmox_lxc_tun` → the tailscale service playbook.

## Before committing

```sh
terraform fmt -check -recursive
terraform validate
tflint
checkov -d .                    # or: trivy config .
```
