## Why

Provisioning today (`playbooks/01_PROVISIONING/*`) drives the Proxmox API from
Ansible, which has no state and therefore no real desired-state model. Three
concrete consequences are visible in the current code:

- **No update path.** `roles/proxmox_lxc/tasks/create.yml` is gated on
  `when: not lxc_exists`, so changing `lxc_memory` or `lxc_disk_gb` on a host
  that already exists silently does nothing. Resizing is a manual PVE action.
- **No teardown path.** Nothing implements `state: absent`. Removing a host from
  `inventory/hosts` leaves the container running on the node forever
  (`retropie01` is already commented out in the inventory while its infra state
  is unknown).
- **Hand-rolled idempotency.** Each provisioning role reimplements
  "does it exist / is there free space" as `preflight.yml` + `set_fact`, ~40
  lines per role that a state file gives for free.

Terraform is the standard answer to exactly this layer, and adopting it here is
directly on the Cloud Security Engineer path: state, `plan` as a reviewable
change gate, drift detection, least-privilege API credentials, and
policy-as-code scanning of infrastructure definitions.

Terraform does **not** replace Ansible. The split is: Terraform owns everything
the Proxmox API owns (guest lifecycle, sizing, network attachment); Ansible owns
everything inside the guest (users, packages, hardening, services). Ansible is
not able to be dropped, and Terraform is not able to converge OS state — using
Terraform `provisioner` blocks for that is discouraged by HashiCorp itself.

## What Changes

- **New `terraform/` tree in this repo** (not a second repo — see design D1),
  with a single root module for the one Proxmox node and reusable
  `modules/proxmox_lxc` + `modules/proxmox_vm` child modules, using the
  `bpg/proxmox` provider.
- **The four live LXCs are `import`ed, not rebuilt.** `pihole01`,
  `partygames01`, `life-dashboard01`, and `tailscale01` are adopted into
  Terraform state with zero downtime and a required empty `plan` diff before the
  change is considered done.
- **BREAKING (workflow):** `playbooks/01_PROVISIONING/lxc_proxmox.yml`,
  `vm_from_template_proxmox.yml`, and `vm_from_iso.yml` are removed, along with
  `roles/proxmox_lxc`, `roles/proxmox_vm_template`, and `roles/proxmox_vm_iso`.
  Creating a guest becomes `terraform apply`, not an Ansible run.
- **`roles/proxmox_lxc_bootstrap` shrinks and moves.** Root password and SSH key
  injection move into the Terraform LXC resource (`initialization.user_account`).
  What remains — creating the unprivileged `ansible` user and its sudo rule — is
  a guest-side concern and moves to a new
  `playbooks/02_BASE_CONFIGURATION/bootstrap.yml`, finally populating the
  currently-empty `02_` category.
- **`roles/proxmox_lxc_tun` stays in Ansible.** The `bpg` provider has no escape
  hatch for raw `lxc.mount.entry` lines in `/etc/pve/lxc/<ctid>.conf`, so TUN
  passthrough remains a post-apply Ansible step (see design D6).
- **Terraform becomes the source of truth for host identity.** vmid, IP,
  hostname, and sizing live in `terraform/environments/homelab/hosts.auto.tfvars`.
  Ansible consumes them through the `cloud.terraform.terraform_state` dynamic
  inventory plugin; `inventory/hosts` is deleted. `group_vars/` and `host_vars/`
  are unchanged and keep working, keyed on the same host names.
- **The `id`-from-last-IP-octet trick is retired.** `inventory/group_vars/proxmox_guest/vars.yml`
  derives vmid from the fourth octet of `ansible_host`; Terraform declares vmid
  and IP as independent, explicit inputs.
- **A dedicated, least-privilege Proxmox API token for Terraform**, separate from
  the existing `root@pam!ansible` token, scoped via a custom PVE role rather than
  reusing root. It is the designated **bootstrap credential**: it lives in a
  `0600` file outside the repo loaded by `direnv`, and it stays outside the
  future Vault by design (design D12).
- **The LXC root passwords are deleted, not migrated.** `lxc_password` on
  `partygames01`/`life-dashboard01` and `vm_ci_password` on `retropie01` solve no
  problem that exists — `pct enter <ctid>` gives passwordless root from the node,
  and every guest is key-authenticated. Deleting them removes an entire secret
  class and reduces Terraform's total secret requirement to exactly one value,
  which is what lets the Vault work in phase B be sequenced cleanly.
- **Validation gates**: `terraform fmt -check`, `terraform validate`, `tflint`,
  and a `checkov`/`trivy config` security scan, added to the
  "Before committing" contract alongside `ansible-lint`.

Explicitly **out of scope** (candidate follow-up changes, listed in design D11):
the HashiCorp Vault LXC and the ansible-vault → Vault migration (**phase B**,
decided but structurally dependent on this change landing first), remote state
backend, PVE RBAC/firewall/SDN as code, Tailscale ACLs as code, Packer images.

## Capabilities

### New Capabilities
- `terraform-provisioning`: Guest lifecycle (LXC and VM create / update / destroy,
  sizing, network attachment, cloud-init and SSH-key seeding) on the Proxmox node
  is declared in Terraform and reconciled from a state file, replacing the
  stateless Ansible provisioning playbooks.
- `terraform-ansible-handoff`: Ansible discovers its hosts and their
  connection details from Terraform state instead of a hand-maintained static
  inventory file, so one definition feeds both layers.

### Modified Capabilities
<!-- None — no existing spec has requirements that change. `openspec/specs/`
     does not exist yet; the only prior change (add-tailscale-subnet-router) has
     not been synced into main specs. -->

## Impact

- **New top-level directory:** `terraform/` (root module + two child modules +
  `.gitignore` entries for `*.tfstate*`, `.terraform/`, `*.tfvars` holding
  secrets).
- **New tooling dependency on the control host:** Terraform (or OpenTofu) — not
  currently installed. Plus `tflint` and `checkov` for the lint gate.
- **New Ansible collection dependency:** `cloud.terraform` in
  `collections/requirements.yml`, for the dynamic inventory plugin.
- **Removed:** `playbooks/01_PROVISIONING/` (all three playbooks),
  `roles/proxmox_lxc`, `roles/proxmox_vm_template`, `roles/proxmox_vm_iso`,
  `inventory/hosts`, `inventory/group_vars/lxc_container_proxmox.yml`,
  `inventory/group_vars/vm_proxmox.yml` (their content becomes tfvars).
- **Reduced/moved:** `roles/proxmox_lxc_bootstrap` → guest-side only, invoked
  from a new `02_BASE_CONFIGURATION/bootstrap.yml`.
- **Unchanged:** every `03_SERVICES` playbook and every application role
  (`pihole`, `partygames`, `life-dashboard`, `tailscale`, `retropie`, `nginx`,
  `nodejs`, `common`). The app-per-LXC, two-repo, build-on-host service model in
  `.claude/CLAUDE.md` is untouched.
- **Secrets:** net count drops. Three LXC/VM root passwords are deleted from
  vaulted `host_vars`; the Terraform API token moves to an environment variable
  sourced from a `0600` file outside the repo (ansible-vault cannot serve it —
  Terraform cannot read vault). `ansible.cfg` currently points
  `vault_password_file` at a `.vault_pass` that **does not exist on disk**; that
  is pre-existing and is addressed in phase B, not here.
- **State file:** git-ignored and backed up with the control host. It holds no
  credential once the root passwords are gone, but it does record the full
  address and container-ID plan.
- **Docs:** `README.md` repo-layout section, `.claude/CLAUDE.md` (repo layout,
  "Before committing", a new Terraform/Ansible boundary section), and a new
  `docs/terraform-ansible-split.md`.
