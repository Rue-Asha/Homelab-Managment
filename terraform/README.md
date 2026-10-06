# Terraform — Proxmox guest lifecycle

Terraform owns everything the Proxmox API owns: guest existence, vmid,
hostname, CPU/memory/swap/disk, network interface and IP, boot behaviour, the
template reference (the homelab LXC template carries the `ansible` user and
its public keys; Terraform seeds no key).

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

Local backend, git-ignored, held **only on `runner01`** at
`~github-runner/.local/state/homelab/terraform.tfstate` — outside the job
workspace, which every job wipes. `scripts/tf-ci.sh` passes the path at init.
The workstation does not run Terraform; read the inventory with
`scripts/fetch-inventory.sh`, or run `terraform plan` on the runner as
`github-runner`. State holds no credential, but it does record the complete
address and container-ID plan.

Backup: `scripts/fetch-state.sh` copies the state to
`~/.local/state/homelab/backups/` on the workstation (timestamped, mode 0600).
Run it after an apply you care about. The node has no vzdump job as of
2026-10-05, so `runner01` is not otherwise backed up.

Losing it is recoverable — `imports.tf` stays in the repo as a template for
re-adoption. Hosts no longer declare a vmid, so fill in each container's real ID
by hand from `pct list` (see the comments in that file) before applying;
without the import, apply creates duplicate containers on the same static IPs.

## First run (rebuild)

The four pre-existing containers are **destroyed and recreated**, not imported.
That was a deliberate choice: importing proves only that Terraform can describe
what already exists, never that it can build it, and every future host takes the
create path. See design D9 in the OpenSpec change for the full reasoning.

Consequences to know before starting:

- **There is no rollback.** The old containers must be gone before Terraform can
  create guests on the same static IPs. Existing guest data is discarded by
  decision — the SQLite databases and uploaded images are not preserved.
- **The LAN loses DNS** while `pihole01` is down, if the router points at it.
  `pihole01` is declared again (see `docs/pihole.md`); set a fallback
  resolver on the router first, or rebuild it last.

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

ansible-playbook ansible/playbooks/01_BASE_CONFIGURATION/bootstrap.yml
ansible-playbook ansible/playbooks/02_SERVICES/<service>.yml -l <host>
```

Before trusting it, run the API preflight: confirm the LXC template exists on
`local`, that `local-lvm` has room, and that the declared sizing matches what
you actually want. That check already caught `pihole01` being declared at
1024 MiB / 8 GiB when the live container ran at 512 / 4.

## Day-2

Apply happens in `.github/workflows/deploy.yml` on `runner01`: a merge to `main`
that touches `terraform/**` runs `plan`, waits for approval in the
`infrastructure` GitHub environment, applies exactly the saved plan, then
deploys. A plan that would delete or replace `runner01` is refused
(`scripts/checks/plan-protected.sh`). For drift detection, `terraform plan` on the
runner as `github-runner`.

Adding a host: add an entry to `hosts.auto.tfvars` and merge. The new guest
comes from the template, so it is reachable as `ansible` without a manual step;
the baseline and service playbooks follow in the same deploy.

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

### Runner credentials

`runner01` applies with its own token, never the workstation's. Create the
`terraform-deploy-node@pve` user, role and token on the node, then write the file
on the workstation (it is not in the repo) and let `deploy_runner.yml` push it
to `~github-runner/.config/homelab/terraform.env`:

```sh
( umask 077; cat > ~/.config/homelab/runner_terraform.env <<'EOF'
PROXMOX_VE_ENDPOINT=https://192.168.0.22:8006/
PROXMOX_VE_API_TOKEN=terraform-deploy-node@pve!<token-id>=<uuid>
TF_VAR_pve_ssh_enabled=false
EOF
)
```

The user lives in the `pve` realm and the token has privilege separation on, so
the role `TerraformProvioning` must be granted on `/` to the **token** itself
(Datacenter → Permissions → API Token Permission); a grant on the user alone
yields `403 … VM.Audit`.

Privileges of `TerraformProvioning`:

```
VM.Allocate  VM.Clone  VM.PowerMgmt  VM.Audit  VM.Console
VM.Config.CPU  VM.Config.Memory  VM.Config.Disk  VM.Config.Network
VM.Config.Options  VM.Config.HWType  VM.Config.CDROM  VM.Config.Cloudinit
VM.Snapshot  VM.Snapshot.Rollback  VM.Migrate  VM.Replicate  VM.Backup
VM.GuestAgent.Audit  VM.GuestAgent.FileRead  VM.GuestAgent.FileWrite
VM.GuestAgent.FileSystemMgmt  VM.GuestAgent.Unrestricted
Datastore.Allocate  Datastore.AllocateSpace  Datastore.AllocateTemplate
Datastore.Audit  SDN.Use
```

Read and `plan` are proven with this set and no SSH. Create and destroy are
proven by the throwaway guest of task 6.3, after which the list is trimmed to
what that run used (candidates: `VM.Console`, `VM.Migrate`, `VM.Replicate`,
`VM.Backup`, `VM.Snapshot*`, `VM.GuestAgent.*`).

The play fails when the file is missing. Rotating the token means editing this
file and rerunning the play.
