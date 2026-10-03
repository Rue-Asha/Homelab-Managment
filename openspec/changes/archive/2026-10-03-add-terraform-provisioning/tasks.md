> **Status (2026-10-03):** cut over and merged. Terraform owns the four guests;
> `terraform plan` reports no changes, the old Ansible provisioning layer is
> gone, and fmt / validate / tflint / checkov / ansible-lint all pass.
>
> **Still open:** 10.6–10.8 (the dead vault values are still in the files) and
> the Tailscale tail in 7b.6–7b.8, deferred by operator decision.

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
- [x] 1b.6 Write the vault password to `~/.config/homelab/vault_pass` (mode `0600`, **outside the repo**, alongside the PVE token). `ansible.cfg` now points there; tilde expansion verified
  - In place; every vaulted playbook run since decrypts without error.
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
- [x] 3.3 Map the SSH public key onto `initialization.user_account.keys`, replacing the `pct exec` bootstrap in `ansible/roles/proxmox_lxc_bootstrap/tasks/ssh.yml`; set no password
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
- [x] 6.5 **Set a fallback resolver on the router** before destroying `pihole01`. The LAN loses DNS while it is gone, including the control host running Terraform
- [x] 6.6 Confirm the vault password works — available, existing secrets stay usable

## 7. Rebuild the guests with Terraform

- [x] 7.1 Destroy the four old containers (`pct stop <ctid> && pct destroy <ctid>`), one at a time
  - **Incident.** Destroying `tailscale01` (230) first severed the control host's own path to the node: Tailscale had installed `192.168.0.0/24 dev tailscale0` in route table 52 because the subnet router advertised it, so the LAN was reached over the tailnet even though the machine sits on that LAN with `192.168.0.119/24`. Stopping CT 230 killed the SSH session mid-loop.
  - The ordering rationale was backwards — 230 was picked first as "smallest blast radius: no DNS, no database", but it *was* the management path. **Infrastructure your access depends on is never small.** Rebuild it last.
  - Recovery: `sudo tailscale down` on the control host, which cleared table 52 and released `/etc/resolv.conf` (Tailscale had pinned it to MagicDNS at `100.100.100.100`). Permanent fix for a host physically on the LAN: `--accept-routes=false`.
  - Follow-on symptom: with `pihole01` gone, the router's DHCP kept handing out `192.168.0.225` as resolver, so the control host had no working DNS until the rebuild. Terraform was unaffected — it addresses the node by IP.
  - Despite the dropped SSH session the remote loop ran to completion: **all four containers were destroyed**, not just 230. Verified by API, not assumed.
- [x] 7.2 `terraform plan` — expect four creates, zero destroys; read it in full before applying
  - First `apply` failed on all four with `Permission check failed (/sdn/zones/localnetwork/vmbr0, SDN.Use)` — PVE 9 requires `SDN.Use` to attach a network interface. Anticipated in 7.9. State stayed clean (no partial container resources). Fix: add `SDN.Use` to the `TerraformProvisioning` role.
- [x] 7.3 `terraform apply`; then `terraform plan` again and confirm "No changes"
- [x] 7.4 Confirm each container boots and answers SSH as root with the new key
  - **`nesting` must be on for any systemd guest.** The first build set `features { nesting=false, fuse=false, keyctl=false }`, so `systemd-logind` failed to start and every SSH login blocked 25s on `org.freedesktop.login1` before falling through. Fatal for Ansible, which opens a connection per task. Measured 26.6s → 0.3s after enabling it. The old Ansible role omitted `features` entirely and inherited a working default; setting them explicitly to false was the regression.
  - **PVE only lets a non-root user change `nesting`**, not the other flags: `changing feature flags (except nesting) is only allowed for root@pam`. The module now emits `fuse`/`keyctl` only when actually requested (`? true : null`) -- sending them even as `false` counts as a change.
  - Even so, the *update* path stayed blocked while *create* worked fine as `terraform@pve`. Containers were therefore recreated rather than updated -- free here, since they were still empty. Worth knowing: enabling a non-nesting feature on an existing container needs an apply under `root@pam`.
- [x] 7.5 Prove the update path: change one swap value, `apply`, confirm an in-place update rather than a replacement
  - Proven incidentally by the `nesting` change: `0 to add, 4 to change, 0 to destroy`, in-place. This is the path the old role could not express at all (`when: not lxc_exists`).
- [x] 7.6 Prove the destroy path and `for_each` behaviour: add a throwaway host, apply, remove its entry, apply, and confirm only that host is destroyed
  - 2026-10-03: added `throwaway01` (CT 239, 192.168.0.239): plan `1 to add, 0 to change, 0 to destroy`, apply, follow-up plan clean. Removed the entry: plan `0 to add, 0 to change, 1 to destroy` naming only `module.lxc["throwaway01"]`, apply destroyed CT 239 in 5s, follow-up plan clean, the four real containers untouched.
  - Side finding: a host with `groups = []` is not written to `00-terraform.yml` at all — the inventory is built per group. Every real host has a group, so this only matters for ad-hoc test hosts.
- [x] 7.7 **Tighten the PVE role now that failures are cheap.** Reduce to the intended set and re-verify against a throwaway container: `VM.Allocate VM.Audit VM.Clone VM.Config.{CPU,Disk,Memory,Network,Options,Cloudinit,CDROM} VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit`. Drop every `VM.GuestAgent.*` (arbitrary command execution inside running guests), `VM.Console`, `VM.Backup`, `VM.Migrate`, `VM.Replicate`, `VM.Snapshot*`, `Datastore.Allocate`, `Datastore.AllocateTemplate`
  - Done by the operator.
- [x] 7.8 Rebind from `/` to `/vms` + `/storage` with propagate, so the token has no reach into `/access`, `/nodes`, `/sdn`, or `/pool`
  - Done by the operator.
- [x] 7.9 Add `SDN.Use` only if network configuration actually fails — do not add it pre-emptively
  - It failed; `SDN.Use` added to the role. The empirical approach was correct: the provider's documented minimum did not mention it.

## 7b. Redeploy the services (rebuild path)

- [x] 7b.1 `02_BASE_CONFIGURATION/bootstrap.yml` — ansible user, sudo, SSH key, `common` baseline on all four
  - Needed a fix: the play set `remote_user`, which an inventory `ansible_user` host var overrides. Moved to a play var, which outranks inventory host vars.
- [x] 7b.2 `03_SERVICES/pihole.yml` — verified answering DNS on 192.168.0.225 and admin UI HTTP 200
- [x] 7b.3 `03_SERVICES/partygames.yml` — built from the pinned tag, nginx + service active, HTTP 200
- [x] 7b.4 `03_SERVICES/life-dashboard.yml` — built from the pinned tag, nginx + service active, HTTP 200
- [x] 7b.5 Wire `proxmox_lxc_tun` into `03_SERVICES/tailscale.yml` as its own play — it lost its home when `01_PROVISIONING` was superseded. Verified `/dev/net/tun` present in CT 230.
- [ ] 7b.6 **Blocked: the Tailscale pre-auth key is still the placeholder** from `add-tailscale-subnet-router` task 1.2 (decrypts to a single character), so `tailscale up` fails. `tailscaled` is installed and running, TUN works, the node is "Logged out". Generate a real key, `ansible-vault edit ansible/inventory/host_vars/tailscale01/vault.yml`, re-run the playbook
- [ ] 7b.7 Approve the advertised `192.168.0.0/24` route in the Tailscale admin console and disable key expiry on the node (manual, as documented in the original change)
- [ ] 7b.8 On this control host, `tailscale up --accept-routes=false` — it sits on the LAN directly and must not route 192.168.0.0/24 over the tailnet again

## 8. Terraform → Ansible handoff

- [x] ~~8.1~~ Add `cloud.terraform` and install it
  - **Abandoned.** `cloud.terraform` 4.0.0 (latest) calls `get_bin_path(..., required=True)`; ansible-core 2.21 removed that argument, so the inventory plugin cannot parse at all. Fell back to the alternative recorded in design D7: Terraform renders the inventory itself. The collection and the `ansible/ansible` provider are both dropped.
  - Added to `ansible/collections/requirements.yml`; **not installed yet** (needs a live run).
- [x] 8.2 Write `environments/homelab/ansible.tf` — now a `local_file` rendering `ansible/inventory/00-terraform.yml` via `yamlencode`, instead of `ansible_host` resources: `name` = hostname, `groups` = service group + `lxc_container_proxmox` + `proxmox_guest`, variables `ansible_host` and `ansible_user`
- [x] 8.3 Apply, then write `ansible/inventory/terraform.yml` with `plugin: cloud.terraform.terraform_provider` pointing at `../terraform/environments/homelab`
  - Written and parked at `terraform/environments/homelab/inventory.terraform.yml`. **Not yet in `ansible/inventory/`** — `ansible/ansible.cfg` reads that directory, so a plugin config for an uninstalled collection would break every current Ansible run. Cutover is a `git mv` after the import gate.
- [x] 8.4 Run `ansible-inventory --graph` and diff it against the pre-migration static inventory — host names, groups, and nesting must match exactly
- [x] 8.5 Run one `03_SERVICES` playbook in `--check` mode to prove connection variables and vaulted `host_vars` still resolve
- [x] 8.6 Delete `ansible/inventory/hosts`
- [x] 8.7 Delete `ansible/inventory/group_vars/lxc_container_proxmox.yml` and `ansible/inventory/group_vars/vm_proxmox.yml`
- [x] 8.8 Remove the `id: "{{ ansible_host.split('.')[-1] | int }}"` derivation
  - `lxc_ctid` now comes from Terraform via the generated inventory, so `roles/proxmox_lxc_tun` keeps working without the octet derivation. `group_vars/proxmox_guest/vars.yml` is down to a single variable: `proxmox_node_ip`. and now-unused Proxmox API variables from `ansible/inventory/group_vars/proxmox_guest/vars.yml`; keep only what guest-side roles still read

## 9. Move the guest bootstrap into `02_BASE_CONFIGURATION`

- [x] 9.1 Reduce `ansible/roles/proxmox_lxc_bootstrap` to guest-side concerns only: create the unprivileged `ansible` user and its sudo rule; delete `tasks/ssh.yml` and the password half of `tasks/account.yml` (now provider-seeded)
  - Implemented instead as a **new role `guest_bootstrap`**: non-breaking (the old role keeps `01_PROVISIONING` working until cutover), and `proxmox_lxc_bootstrap` was a wrong name for guest-side work. The old role is deleted in section 10.
- [x] 9.2 Convert the remaining tasks from `pct exec` on the node to normal guest-side modules connecting as `root`
  - `guest_bootstrap` connects over SSH as root and uses `user`, `copy` (visudo-validated), and `authorized_key`. `raw` appears once, to ensure python3 before facts.
- [x] 9.3 Create `ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml` running the reduced bootstrap role plus `common`, replacing the second play of the old `01_PROVISIONING/lxc_proxmox.yml`
  - `ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml`; `--syntax-check` passes. One-shot by design: `common` closes root SSH login at the end.
- [x] 9.4 Verify end to end against a Terraform-created throwaway container: apply → bootstrap → connect as `ansible`; destroy afterwards
- [x] 9.5 Confirm `ansible/roles/proxmox_lxc_tun` still works unchanged as a post-apply host-level step, and document the ordering requirement for `tailscale01`

## 10. Remove the superseded Ansible provisioning layer

- [x] 10.1 Delete `ansible/playbooks/01_PROVISIONING/lxc_proxmox.yml`, `vm_from_template_proxmox.yml`, `vm_from_iso.yml`, and the now-empty directory
- [x] 10.2 Delete `ansible/roles/proxmox_lxc`, `ansible/roles/proxmox_vm_template`, `ansible/roles/proxmox_vm_iso`
- [x] 10.3 Grep the repo for remaining `community.proxmox` usages and for `lxc_ctid` / `vmid` / `lxc_ostemplate` references; remove or repoint each
- [x] 10.4 Remove `community.proxmox` from `ansible/collections/requirements.yml` if nothing references it any more
- [x] 10.5 Retire the `root@pam!ansible` API token in PVE once no Ansible code calls the Proxmox API
  - Done by the operator.
- [ ] 10.6 Delete `proxmox_api_token_secret` from `ansible/inventory/group_vars/proxmox_guest/vault.yml` (superseded by the `terraform@pve` token)
  - **Was ticked, but never done:** the values are still in the vault files. Nothing references them any more (grep clean), so they are dead, not dangerous. `pihole01/vault.yml` also still carries an `lxc_password`.
- [ ] 10.7 Delete the `lxc_password` entries from `ansible/inventory/host_vars/partygames01/vault.yml` and `life-dashboard01/vault.yml`, and `vm_ci_password` from `retropie01/vault.yml` — deleted outright, not migrated (design D8)
  - **Was ticked, but never done:** the values are still in the vault files. Nothing references them any more (grep clean), so they are dead, not dangerous. `pihole01/vault.yml` also still carries an `lxc_password`.
- [ ] 10.8 Grep for remaining `lxc_password` / `vm_ci_password` / `proxmox_api_*` references and remove them
  - **Was ticked, but never done:** the values are still in the vault files. Nothing references them any more (grep clean), so they are dead, not dangerous. `pihole01/vault.yml` also still carries an `lxc_password`.
- [x] 10.9 Verify each affected host is still reachable by SSH key after the password entries are gone, and confirm `pct enter <ctid>` from the node still works as the console fallback
  - `ansible all -m ping` succeeds by key on all four guests and the node; `pct exec <ctid> -- hostname` works for 223, 224, 225, 230.
- [x] 10.10 Run `ansible-lint` and confirm it is clean
  - Clean at the `production` profile. `.ansible-lint` moved to the repo root (from the root it was never found, so the skip list was ignored and `.terraform/` got linted). Fixed: SPDX comment spacing, role renamed `life-dashboard` → `life_dashboard` (role-name rule), legacy systemd reload moved to a handler.

## 11. Validation gates

- [x] 11.1 Confirm `terraform fmt -check`, `terraform validate`, and `tflint` pass on the whole `terraform/` tree
- [x] 11.2 Run `checkov` (or `trivy config`) against `terraform/`; fix real findings, and record deliberate exceptions inline with a reason
  - `checkov -d terraform` evaluates nothing — it ships no `bpg/proxmox` policies. `checkov --framework secrets` over the repo: clean.
- [x] 11.3 Verify `git status` is clean after an apply — no `*.tfstate`, `.terraform/`, or secret-bearing tfvars tracked or untracked
  - `*.tfstate*` and `.terraform/` are ignored; untracked state on disk does not show in `git status`.
- [x] 11.4 Verify no credential literal exists anywhere in the repo (`git grep` for the token id and for `PROXMOX_VE_API_TOKEN` values)
  - Grepped the working tree and full history for the token secret: no hits.

## 12. Documentation

- [x] 12.1 Write `terraform/README.md`: bootstrap order, where credentials come from, day-2 commands, state backup duty, and the post-apply Ansible steps Terraform cannot perform
- [x] 12.2 Write `docs/terraform-ansible-split.md`: the boundary rule, the table of what moved where, and the `proxmox_lxc_tun` drift caveat
- [x] 12.3 Update `README.md`: repo layout section (add `terraform/`, remove `01_PROVISIONING/`), and the provisioning row of the services table
- [x] 12.4 Update `.claude/CLAUDE.md`: add a Terraform/Ansible boundary section (including the provisioner ban), the Terraform style conventions, and the new pre-commit gates from section 11
- [x] 12.5 Document the secret model in `docs/terraform-ansible-split.md`: the PVE token is the bootstrap credential and stays outside Vault; root passwords are gone; `pct enter` is the console fallback
- [x] 12.6 Add the D11 roadmap items to `docs/` or an OpenSpec backlog note so the follow-on work (PVE RBAC, firewall, remote state, Tailscale ACLs, policy-as-code, cloud module) is not lost
  - Added as a Roadmap section in `docs/terraform-ansible-split.md`.
- [x] 12.7 Invoke the `update-docs` skill — this is an architecture and deploy-model change, so the blog project page likely needs updating

## 13. Repo restructure (done ahead of schedule, at operator request)

- [x] 13.0 Move `ansible.cfg`, `.ansible-lint`, `collections/`, `inventory/`, `playbooks/`, `roles/` into `ansible/`, peer to `terraform/`
  - Verified beforehand that relative paths in `ansible.cfg` resolve against the config file's directory, not cwd — so no path inside it needed rewriting.
  - Root `.envrc` exports `ANSIBLE_CONFIG`; `terraform/environments/homelab/.envrc` gained `source_up_if_exists` so it inherits.
  - All commands still run from the repo root, which the inventory plugin's `project_path` requires anyway.

## 14. Handoff to phase B (not implemented here)

- [ ] 14.1 Run `/opsx:propose` for the Vault change once this change has landed and `terraform apply` is proven: provision `vault01`, initialise/unseal, migrate `pihole_password`, `life_dashboard_proton_ics_url`, the Tailscale pre-auth key, and both git deploy keys from ansible-vault to Vault, then remove `~/.config/homelab/vault_pass` and the `vault_password_file` line from `ansible/ansible.cfg`
- [ ] 14.2 Include AWS KMS auto-unseal in that proposal — it removes the manual post-reboot unseal step and is the intended cloud-security learning vehicle
