> **Status:** the Terraform layer is written, validated, and planned against the
> live node — `fmt`, `validate`, `tflint`, and `terraform plan` all pass, and the
> plan matches the four running containers exactly (`9 to add, 0 to change,
> 0 to destroy`). All prerequisites and credential recovery are done.
>
> **Nothing has been destroyed or rewired yet.** The existing Ansible
> provisioning path is still the active one. The next step (section 7) is the
> first irreversible one, and backups were dropped by operator decision — the
> old guests and their data are being discarded deliberately.

## 1. Prerequisites (operator, out-of-band)

- [x] 1.1 Install Terraform (>= 1.7, for `for_each` in `import` blocks) on the control host; verify `terraform version`
- [x] 1.2 Install `tflint` and `checkov` (or `trivy config`) on the control host
- [x] 1.3 Create a PVE user `terraform@pve` and a **custom role** with the minimum privileges for guest lifecycle (start from the provider's documented minimum: `VM.Allocate`, `VM.Config.*`, `VM.PowerMgmt`, `VM.Audit`, `Datastore.AllocateSpace`, `Datastore.Audit`); assign it at the appropriate path
  - Created, but **much broader than designed**: 27 privileges (PVEVMAdmin + PVEDatastoreAdmin) bound at `/`, including `VM.GuestAgent.Unrestricted`, `VM.GuestAgent.FileWrite`, `VM.Console`, and `Datastore.Allocate`. No `Permissions.Modify`/`User.Modify`/`Sys.*`, so it cannot escalate itself. Tightening deferred to 7.7 — see there.
- [x] 1.4 Create an API token for `terraform@pve` and write the credentials to `~/.config/homelab/terraform.env` (mode `0600`, **outside the repo**) exporting `PROXMOX_VE_ENDPOINT` and `PROXMOX_VE_API_TOKEN`. This is the designated bootstrap credential — it stays outside Vault permanently (design D12)
- [x] 1.5 Add a committed `terraform/environments/homelab/.envrc` (`dotenv_if_exists ~/.config/homelab/terraform.env`) and run `direnv allow`; `direnv` is already installed
- [~] 1.6 ~~Take a Proxmox backup or snapshot before any Terraform run~~ — **dropped** (operator decision: guests are rebuilt from scratch, existing data is not wanted)
- [x] 1.7 Record the live configuration of all four containers
  - Done via the API preflight, not `pct config`. Found pihole01 at 512 MiB / 4 GiB where the catalogue claimed 1024 / 8.

## 1b. Recover lost credentials (unplanned — discovered during validation)

The control host had neither `~/.ssh/Proxmox` nor `.vault_pass`. The node itself
is reachable (API answers 401), so only credentials are missing.

- [x] 1b.1 Generate a replacement ed25519 keypair at `~/.ssh/Proxmox`
- [x] 1b.2 Distribute the new public key via the PVE web shell: append to `/root/.ssh/authorized_keys` on the node, and to `/home/ansible/.ssh/authorized_keys` in CTs 223, 224, 225, 230 (`restore-key.sh`)
- [x] 1b.3 Fill the real token into `~/.config/homelab/terraform.env` (template created, mode 0600)
- [x] 1b.4 **Determine whether the ansible-vault password still exists.** If not, `pihole_password`, `life_dashboard_proton_ics_url`, the Tailscale pre-auth key, and both git deploy keys are unrecoverable and must be regenerated — fold that into phase B
  - Vault password is available; existing secrets stay usable, nothing needs regenerating.
- [x] 1b.5 Verify SSH works again: `ssh -i ~/.ssh/Proxmox root@192.168.0.22` and `ssh -i ~/.ssh/Proxmox ansible@192.168.0.225`

## 2. Repository scaffolding

- [x] 2.1 Create the `terraform/` tree: `environments/homelab/` and `modules/proxmox_lxc/`, `modules/proxmox_vm/`
- [x] 2.2 Add `.gitignore` entries: `*.tfstate`, `*.tfstate.*`, `.terraform/`, `crash*.log`, `secrets.auto.tfvars`
- [x] 2.3 Write `environments/homelab/versions.tf`: `required_version`, `bpg/proxmox` pinned with `~>`, `ansible/ansible` provider
- [x] 2.4 Write `environments/homelab/providers.tf` reading endpoint and token from environment variables only — no credential literals
- [x] 2.5 Run `terraform init`; commit `.terraform.lock.hcl`
  - bpg/proxmox resolved to **0.111.1**; constraint tightened from `~> 0.60` (which allowed it) to `~> 0.111`. Lock file committed.

## 3. `modules/proxmox_lxc`

- [x] 3.1 Write `variables.tf`: `hostname`, `vmid`, `ipv4_address`, `gateway`, `cores`, `memory`, `swap`, `disk_gb`, `datastore`, `template_file_id`, `bridge`, `vlan_id` (optional), `ssh_public_keys`, `unprivileged`, `start_on_boot`. **No `root_password` variable** — root passwords are deleted, not migrated (design D8)
- [x] 3.2 Write `main.tf` with a single `proxmox_virtual_environment_container` resource — no `count`/`for_each` inside the module
- [x] 3.3 Map the SSH public key onto `initialization.user_account.keys`, replacing the `pct exec` bootstrap in `roles/proxmox_lxc_bootstrap/tasks/ssh.yml`; set no password
- [x] 3.4 Write `outputs.tf`: `vmid`, `ipv4_address`, `hostname`
- [x] 3.5 Set homelab defaults (`unprivileged = true`, `start_on_boot = true`, swap `512`, bridge `vmbr0`) so a host entry stays short

## 4. `modules/proxmox_vm`

- [x] 4.1 Write `variables.tf` covering both provisioning paths: a `clone` source (template name/vmid) **or** a `cdrom` file id, plus cores/sockets/memory/disk/bridge and cloud-init settings (user, ssh keys, ip config, nameservers) — no cloud-init password, per design D8
- [x] 4.2 Write `main.tf` with one `proxmox_virtual_environment_vm` resource covering clone-from-template and ISO-attached-shell cases (design D10)
- [x] 4.3 Write `outputs.tf`: `vmid`, `ipv4_address`, `hostname`
- [x] 4.4 Confirm the module is not instantiated yet — `retropie01` is unprovisioned and is deliberately **not** imported

## 5. Host catalogue (root module)

- [x] 5.1 Write `variables.tf` for shared settings absorbed from `group_vars/lxc_container_proxmox.yml` and `vm_proxmox.yml`: bridge, gateway, CIDR, rootfs datastore, template file id, SSH public key path
- [x] 5.2 Write `hosts.auto.tfvars` with the `lxc_hosts` map for the four live containers, using their **actual** vmid, IP, cores, memory, swap, and disk from task 1.6 — vmid declared explicitly, not derived from the IP
- [x] 5.3 Write `containers.tf`: `module "lxc"` with `for_each = var.lxc_hosts` (never `count`)
- [x] 5.4 Write `vms.tf` with `module "vm"` over an empty `vm_hosts` map
- [x] 5.5 Write `outputs.tf` exposing hostname → vmid/IP for operator inspection
- [x] 5.6 Confirm the root module needs **no** secret-bearing tfvars file at all — the PVE token is the only secret and it arrives via environment variables
- [x] 5.7 Run `terraform validate` and `terraform fmt`
  - `validate` passes against the real provider schema, so the container/VM block structures are confirmed. `fmt` and `tflint --recursive` clean.

## 6. Pre-rebuild (backups dropped by operator decision)

The original plan led with backups. The operator chose to discard the existing
guests and their data outright, so 6.1-6.4 are gone. What remains is not about
data but about availability.

- [~] 6.1 ~~vzdump all four containers~~ — dropped
- [~] 6.2 ~~Copy /var/lib/{life-dashboard,partygames} off the containers~~ — dropped; the SQLite databases and uploaded images are intentionally discarded
- [~] 6.3 ~~Record `pct config`~~ — superseded by the API preflight (see 1.7)
- [~] 6.4 ~~Note hand-configured Pi-hole state~~ — dropped; Pi-hole is set up fresh from the role
- [ ] 6.5 **Set a fallback resolver on the router** before destroying `pihole01`. The LAN loses DNS while it is gone, including the control host running Terraform
- [x] 6.6 Confirm the vault password works — available, existing secrets stay usable

## 7. Rebuild the guests with Terraform

- [ ] 7.1 Destroy the four old containers (`pct stop <ctid> && pct destroy <ctid>`), one at a time
- [ ] 7.2 `terraform plan` — expect four creates, zero destroys; read it in full before applying
- [ ] 7.3 `terraform apply`; then `terraform plan` again and confirm "No changes"
- [ ] 7.4 Confirm each container boots and answers SSH as root with the new key
- [ ] 7.5 Prove the update path: change one swap value, `apply`, confirm an in-place update rather than a replacement
- [ ] 7.6 Prove the destroy path and `for_each` behaviour: add a throwaway host, apply, remove its entry, apply, and confirm only that host is destroyed
- [ ] 7.7 **Tighten the PVE role now that failures are cheap.** Reduce to the intended set and re-verify against a throwaway container: `VM.Allocate VM.Audit VM.Clone VM.Config.{CPU,Disk,Memory,Network,Options,Cloudinit,CDROM} VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit`. Drop every `VM.GuestAgent.*` (arbitrary command execution inside running guests), `VM.Console`, `VM.Backup`, `VM.Migrate`, `VM.Replicate`, `VM.Snapshot*`, `Datastore.Allocate`, `Datastore.AllocateTemplate`
- [ ] 7.8 Rebind from `/` to `/vms` + `/storage` with propagate, so the token has no reach into `/access`, `/nodes`, `/sdn`, or `/pool`
- [ ] 7.9 Add `SDN.Use` only if network configuration actually fails — do not add it pre-emptively

## 8. Terraform → Ansible handoff

- [ ] 8.1 Add `cloud.terraform` to `collections/requirements.yml` and install it
  - Added to `collections/requirements.yml`; **not installed yet** (needs a live run).
- [x] 8.2 Write `environments/homelab/ansible.tf` with `ansible_host` resources: `name` = hostname, `groups` = service group + `lxc_container_proxmox` + `proxmox_guest`, variables `ansible_host` and `ansible_user`
- [x] 8.3 Apply, then write `inventory/terraform.yml` with `plugin: cloud.terraform.terraform_provider` pointing at `../terraform/environments/homelab`
  - Written and parked at `terraform/environments/homelab/inventory.terraform.yml`. **Not yet in `inventory/`** — `ansible.cfg` reads that directory, so a plugin config for an uninstalled collection would break every current Ansible run. Cutover is a `git mv` after the import gate.
- [ ] 8.4 Run `ansible-inventory --graph` and diff it against the pre-migration static inventory — host names, groups, and nesting must match exactly
- [ ] 8.5 Run one `03_SERVICES` playbook in `--check` mode to prove connection variables and vaulted `host_vars` still resolve
- [ ] 8.6 Delete `inventory/hosts`
- [ ] 8.7 Delete `inventory/group_vars/lxc_container_proxmox.yml` and `inventory/group_vars/vm_proxmox.yml`
- [ ] 8.8 Remove the `id: "{{ ansible_host.split('.')[-1] | int }}"` derivation and now-unused Proxmox API variables from `inventory/group_vars/proxmox_guest/vars.yml`; keep only what guest-side roles still read

## 9. Move the guest bootstrap into `02_BASE_CONFIGURATION`

- [x] 9.1 Reduce `roles/proxmox_lxc_bootstrap` to guest-side concerns only: create the unprivileged `ansible` user and its sudo rule; delete `tasks/ssh.yml` and the password half of `tasks/account.yml` (now provider-seeded)
  - Implemented instead as a **new role `guest_bootstrap`**: non-breaking (the old role keeps `01_PROVISIONING` working until cutover), and `proxmox_lxc_bootstrap` was a wrong name for guest-side work. The old role is deleted in section 10.
- [x] 9.2 Convert the remaining tasks from `pct exec` on the node to normal guest-side modules connecting as `root`
  - `guest_bootstrap` connects over SSH as root and uses `user`, `copy` (visudo-validated), and `authorized_key`. `raw` appears once, to ensure python3 before facts.
- [x] 9.3 Create `playbooks/02_BASE_CONFIGURATION/bootstrap.yml` running the reduced bootstrap role plus `common`, replacing the second play of the old `01_PROVISIONING/lxc_proxmox.yml`
  - `playbooks/02_BASE_CONFIGURATION/bootstrap.yml`; `--syntax-check` passes. One-shot by design: `common` closes root SSH login at the end.
- [ ] 9.4 Verify end to end against a Terraform-created throwaway container: apply → bootstrap → connect as `ansible`; destroy afterwards
- [ ] 9.5 Confirm `roles/proxmox_lxc_tun` still works unchanged as a post-apply host-level step, and document the ordering requirement for `tailscale01`

## 10. Remove the superseded Ansible provisioning layer

- [ ] 10.1 Delete `playbooks/01_PROVISIONING/lxc_proxmox.yml`, `vm_from_template_proxmox.yml`, `vm_from_iso.yml`, and the now-empty directory
- [ ] 10.2 Delete `roles/proxmox_lxc`, `roles/proxmox_vm_template`, `roles/proxmox_vm_iso`
- [ ] 10.3 Grep the repo for remaining `community.proxmox` usages and for `lxc_ctid` / `vmid` / `lxc_ostemplate` references; remove or repoint each
- [ ] 10.4 Remove `community.proxmox` from `collections/requirements.yml` if nothing references it any more
- [ ] 10.5 Retire the `root@pam!ansible` API token in PVE once no Ansible code calls the Proxmox API
- [ ] 10.6 Delete `proxmox_api_token_secret` from `inventory/group_vars/proxmox_guest/vault.yml` (superseded by the `terraform@pve` token)
- [ ] 10.7 Delete the `lxc_password` entries from `inventory/host_vars/partygames01/vault.yml` and `life-dashboard01/vault.yml`, and `vm_ci_password` from `retropie01/vault.yml` — deleted outright, not migrated (design D8)
- [ ] 10.8 Grep for remaining `lxc_password` / `vm_ci_password` / `proxmox_api_*` references and remove them
- [ ] 10.9 Verify each affected host is still reachable by SSH key after the password entries are gone, and confirm `pct enter <ctid>` from the node still works as the console fallback
- [ ] 10.10 Run `ansible-lint` and confirm it is clean

## 11. Validation gates

- [x] 11.1 Confirm `terraform fmt -check`, `terraform validate`, and `tflint` pass on the whole `terraform/` tree
- [ ] 11.2 Run `checkov` (or `trivy config`) against `terraform/`; fix real findings, and record deliberate exceptions inline with a reason
- [ ] 11.3 Verify `git status` is clean after an apply — no `*.tfstate`, `.terraform/`, or secret-bearing tfvars tracked or untracked
- [ ] 11.4 Verify no credential literal exists anywhere in the repo (`git grep` for the token id and for `PROXMOX_VE_API_TOKEN` values)

## 12. Documentation

- [x] 12.1 Write `terraform/README.md`: bootstrap order, where credentials come from, day-2 commands, state backup duty, and the post-apply Ansible steps Terraform cannot perform
- [x] 12.2 Write `docs/terraform-ansible-split.md`: the boundary rule, the table of what moved where, and the `proxmox_lxc_tun` drift caveat
- [ ] 12.3 Update `README.md`: repo layout section (add `terraform/`, remove `01_PROVISIONING/`), and the provisioning row of the services table
- [x] 12.4 Update `.claude/CLAUDE.md`: add a Terraform/Ansible boundary section (including the provisioner ban), the Terraform style conventions, and the new pre-commit gates from section 11
- [x] 12.5 Document the secret model in `docs/terraform-ansible-split.md`: the PVE token is the bootstrap credential and stays outside Vault; root passwords are gone; `pct enter` is the console fallback
- [ ] 12.6 Add the D11 roadmap items to `docs/` or an OpenSpec backlog note so the follow-on work (PVE RBAC, firewall, remote state, Tailscale ACLs, policy-as-code, cloud module) is not lost
- [ ] 12.7 Invoke the `update-docs` skill — this is an architecture and deploy-model change, so the blog project page likely needs updating

## 13. Handoff to phase B (not implemented here)

- [ ] 13.1 Run `/opsx:propose` for the Vault change once this change has landed and `terraform apply` is proven: provision `vault01`, initialise/unseal, migrate `pihole_password`, `life_dashboard_proton_ics_url`, the Tailscale pre-auth key, and both git deploy keys from ansible-vault to Vault, then remove `.vault_pass` and the `vault_password_file` line from `ansible.cfg`
- [ ] 13.2 Include AWS KMS auto-unseal in that proposal — it removes the manual post-reboot unseal step and is the intended cloud-security learning vehicle
