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

```
environments/homelab/     the only root module — one node, one state
  hosts.auto.tfvars       the host catalogue (replaced inventory/hosts)
  imports.tf              adoption of the four pre-existing containers
  ansible.tf              inventory metadata consumed by Ansible
modules/proxmox_lxc/      one container
modules/proxmox_vm/       one VM, clone-from-template or ISO shell
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

## First run (migration)

Order matters; do not skip the gate.

```sh
cd terraform/environments/homelab
terraform init                  # commit the resulting .terraform.lock.hcl
terraform plan                  # imports the four live containers
```

**Gate:** the plan must end up reporting *no changes* for all four containers.

If it proposes a change, the **configuration** is wrong — fix
`hosts.auto.tfvars` or the module defaults until it matches the live container.
Never modify a container to match the config. A proposed `destroy` or
`replace` of a running container is a hard stop: back out and re-check.

```sh
terraform apply                 # writes the imported resources into state
terraform plan                  # must say "No changes"
```

Then verify the services still answer: Pi-hole DNS, both web services, and the
Tailscale route.

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

`roles/proxmox_lxc_tun` writes raw `lxc.mount.entry` lines into
`/etc/pve/lxc/<ctid>.conf` for `/dev/net/tun` passthrough on `tailscale01`. The
provider models container config as typed attributes with no escape hatch for
arbitrary `lxc.*` keys, so this stays a host-level Ansible role delegated to the
node.

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
