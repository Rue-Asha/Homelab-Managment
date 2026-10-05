## Why

A fresh guest is not manageable until a root-only, one-shot `bootstrap.yml` has created the `ansible` user and a manual `deploy_runner.yml` + bootstrap re-run has authorised the deploy key. One key (`~/.ssh/Proxmox`) opens the Proxmox node, guest root and the `ansible` account, so it cannot be scoped or rotated per purpose. Terraform only runs from the workstation, so infrastructure changes bypass the merge-to-main flow that already deploys services.

## What Changes

- Build a custom Debian 13 **LXC** template (`homelab-debian-13-<version>.tar.zst`) from the stock one with a repo script: `ansible` user, passwordless sudo, python3, the guest and deploy **public** keys, SSH hardening drop-in. Root has no key.
- Stop seeding root keys from Terraform (`initialization.user_account.keys`); `bootstrap.yml` loses its root-connecting play and the `raw` python step.
- Keep `guest_bootstrap`'s `exclusive` authorized_keys task as the source of truth for rotation. The template only seeds first contact.
- Template version bumps must not force-replace existing containers (`ignore_changes` on the operating system block).
- Split `~/.ssh/Proxmox` into four credentials: **node key** (workstation → `proxmox1`: provider SSH fallback, `proxmox_lxc_tun`), **guest key** (workstation → `ansible@guests`), **deploy key** (runner → `ansible@guests`, exists), **runner node credentials** (runner's own `terraform@pve` API token plus a scoped node SSH user, or none if the provider fallback is avoidable).
- Run Terraform from `runner01` (widened, no second runner): new `terraform` workflow on push to `main` → plan → `production` environment approval → apply the saved plan. No plan on pull requests.
- **`runner01` is the only place Terraform runs and holds the only copy of the state** (local backend outside the job workspace). The workstation no longer plans or applies; it reads the rendered inventory from the runner.
- Resolve the committed `ansible/inventory/00-terraform.yml` regeneration loop (apply on the runner must not need to push to `main`).
- Sequence `terraform` before `deploy`; close the new-guest gap (host-key pinning and egress allowlist currently need a manual `deploy_runner.yml` run).
- Terraform must never destroy or replace `runner01`.
- **BREAKING (security boundary):** `runner01` gains network reach to `proxmox1` (API 8006, and SSH if needed) plus the provider registry. This reverses "`proxmox1` is dropped outright". Anyone who can merge to `main` can then change the hypervisor; risk accepted by the user in exchange for one runner. Mitigations: dedicated token and role, `production` environment approval, apply of a reviewed saved plan, firewall allowlist for exactly `proxmox1:8006`.

## Capabilities

### New Capabilities
- `guest-template`: the custom LXC template, what it contains, how it is built and versioned, and how Terraform references it.
- `credential-separation`: the four distinct credentials, what each may reach, and where each lives.

### Modified Capabilities
- `deploy-runner`: runner may reach `proxmox1` API; deploy key still never authorised on the node or on `runner01`; Terraform tooling and credentials on the runner.
- `terraform-provisioning`: Terraform runs from the runner with remote locked state; plan/approve/apply flow; no root key seeding; runner is protected from destroy.
- `terraform-ansible-handoff`: inventory rendering no longer requires a committed-file push loop; run order changes (no root bootstrap).
- `continuous-deployment`: `terraform` job precedes `deploy` on the same push.

## Impact

- `terraform/modules/proxmox_lxc`, `terraform/environments/homelab/{containers,providers,variables,ansible}.tf`, backend config.
- `ansible/roles/{guest_bootstrap,github_runner,egress_firewall,common}`, `bootstrap.yml`, `deploy_runner.yml`, `ansible.cfg`, group vars.
- New: template build script, `.github/workflows/terraform.yml`, `ci/` pins for terraform.
- Docs: `docs/deploy-runner.md`, `docs/terraform-ansible-split.md`, `terraform/README.md`, `.claude/CLAUDE.md` boundary text.
- Operator action: copy the existing state to the runner once, then generate the four key pairs once, update `~/.config/homelab/`, rebuild the template, then re-key existing guests via `guest_bootstrap`.

## Non-Goals

- A separate Terraform runner (decided against; revisit if the widened-runner risk becomes unacceptable).
- A remote state backend (MinIO/S3). State stays on the runner; roadmap item 4 is not done by this change.
- Workstation `plan`/`apply`. Reading a plan means reading the approval summary or running Terraform on the runner.
- Templates for VMs (the `clone_vmid` path is unchanged) or Packer.
- Vault migration, PVE users/roles as code, Proxmox firewall as code.
- Auto-apply on merge without approval.
- Rebuilding or re-templating existing guests; they are re-keyed in place.
- Managing the custom template as a Terraform resource.

## Appetite

Two evenings: template + key split + bootstrap trim in the first, runner workflow in the second. Exceeding that means cutting the runner work into its own change.

## Done criteria

- [ ] A new LXC created from the template is reachable as `ansible` from the workstation and from the runner with no root login and no manual step.
- [ ] `bootstrap.yml` contains no root-connecting play; root SSH keys are absent on a fresh guest.
- [ ] Four distinct key pairs exist; the guest key does not open `proxmox1`, the node key does not open any guest.
- [ ] Bumping the template version produces no replacement in `terraform plan` for existing containers.
- [ ] A merge to `main` that changes `hosts.auto.tfvars` runs plan, waits for `production` approval, applies the saved plan, then deploys.
- [ ] Terraform state exists only on `runner01`, outside the job workspace, and survives the workspace wipe; the workstation can fetch the inventory from it.
- [ ] A plan that would destroy `runner01` is refused.
- [ ] `proxmox1` is reachable from the runner only on the API port; guest-key and deploy-key SSH to `proxmox1` is refused.
- [ ] `scripts/proof.sh --all` is green.
