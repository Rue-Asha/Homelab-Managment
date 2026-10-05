## 1. Spike S9: pin and pre-seed Pi-hole v6
> unit: depends=none · scope=S9 · files=openspec/changes/add-pihole/design.md
- [x] 1.1 Read upstream `pi-hole/pi-hole` at its latest v6 tag (`automated install/basic-install.sh`, unattended-install docs, `pihole.toml` / `setupVars.conf` handling) in the scratchpad; nothing runs on a real host
- [x] 1.2 Answer the four questions under "Spike result" in design.md (seeded-config format, version pin without `master`, git-tag fallback needed or not, FTL :53/:80 in the unprivileged LXC)
- [x] 1.3 Name a concrete `pihole_version` value and the exact install command shape; amend `## Contracts` if the variable set changes

## 2. Declare pihole01 in Terraform
> unit: depends=none · scope=S1 · files=terraform/environments/homelab/hosts.auto.tfvars
- [x] 2.1 Add the `pihole01` entry (vmid 225, 192.168.0.225/24, group `pihole`, `runner01`'s `template_file_id`, 1 core / 512 MiB / 512 MiB swap / 4 GiB, tags `dns`, `terraform`) with a short comment on the retired predecessor
- [x] 2.2 Run `terraform fmt -check -recursive` and `terraform validate`, then `scripts/proof.sh --all`; do not run plan/apply

## 3. Deploy mapping fixtures for pihole
> unit: depends=none · scope=S6 · files=scripts/tests/deploy-targets.sh
- [x] 3.1 Extend the synthetic tree in `scripts/tests/deploy-targets.sh` with group `pihole` / host `pihole01`, role `pihole`, playbook `pihole.yml` and `host_vars/pihole01/vars.yml`; update the `ALL` expectation
- [x] 3.2 Write the five scenarios (role change, version bump, group_vars, terraform-only, two services) named after their scenario titles; run them, expect green because the script is generic
- [x] 3.3 Only if a fixture fails, fix `scripts/deploy-targets.sh` minimally and report it under deviations; run `scripts/proof.sh --all`

## 4. The pihole role
> unit: depends=1 · scope=S2,S3,S4 · files=ansible/roles/pihole/**
- [x] 4.1 Restore the role from `efa9f49^` (`git show efa9f49^:<path>`), drop `info.yml` and `SETUP_INFO.txt.j2`, replace the placeholder README with a real one, set `meta/main.yml` to current platforms
- [x] 4.2 `defaults/main.yml` and `tasks/main.yml` per `## Contracts` (import-only hub: `prepare`, `packages`, `install`, `configure`, `service`, `verify`); `packages.yml` as one apt list, without `upgrade: dist`
- [x] 4.3 `prepare.yml` and `install.yml` per the spike result: pinned version, seeded config from a template, skipped when `pihole_version` is already installed, fails before touching a running install when the pin is unavailable, no lighttpd, no unpinned `curl | bash`
- [x] 4.4 `configure.yml`: assert `pihole_password` is defined with a clear message; apply it only when it changed, `no_log`, with `changed_when`; `service.yml` and the `pihole_restart_ftl` handler so FTL restarts only on change
- [x] 4.5 `verify.yml`: flush handlers, `dig @127.0.0.1` and `GET` of the admin URL with retries, fail the play on failure, no vaulted value used
- [x] 4.6 `ansible-lint` on the role and `scripts/proof.sh --all`

## 5. Playbook and host vars
> unit: depends=1 · scope=S5 · files=ansible/playbooks/03_SERVICES/pihole.yml, ansible/inventory/host_vars/pihole01/vars.yml
- [x] 5.1 Write `03_SERVICES/pihole.yml` per `## Contracts` (`hosts: pihole`, `become: true`, `common` then `pihole`, comments like `life-manager.yml`)
- [x] 5.2 Write `host_vars/pihole01/vars.yml` with `pihole_version` from the spike (read the spike result from the merged `design.md`; the variable name is fixed in Contracts); do not create `vault.yml`
- [x] 5.3 `ansible-playbook --syntax-check`, `ansible-lint`, `scripts/proof.sh --all`

## 6. Docs
> unit: depends=1 · scope=S8 · files=docs/pihole.md, terraform/README.md, docs/tailscale-subnet-router.md
- [x] 6.1 Write `docs/pihole.md`: what it is, first-time apply order (router fallback, vault file, plan/apply, commit regenerated `00-terraform.yml`, bootstrap, `--check`, real run, `dig` check), version bump via PR, recovery; state the DNS-outage risk and the router-fallback step as manual
- [x] 6.2 One-paragraph correction in `terraform/README.md` and `docs/tailscale-subnet-router.md` where pihole01 is described as removed
- [x] 6.3 `scripts/proof.sh --all`

## 7. Lint housekeeping
> unit: depends=4,5 · scope=S7 · files=.ansible-lint
- [ ] 7.1 Remove the pihole-related skips (`no-changed-when`, `var-naming[no-role-prefix]`) and run `ansible-lint`; keep, with a reason that is true of the new role, only those that still fail
- [ ] 7.2 `scripts/proof.sh --all` green

## 8. Rollout (Rue's hands)
> unit: depends=3,4,5,6,7 · scope=none · files=ansible/inventory/host_vars/pihole01/vault.yml, ansible/inventory/00-terraform.yml
- [ ] 8.1 ⚠ irreversible: Rue creates `host_vars/pihole01/vault.yml` with `ansible-vault` (`pihole_password`, inline `!vault |`); the builder does not write it
- [ ] 8.2 ⚠ irreversible: Rue runs `terraform plan` (expect one new LXC) then `terraform apply`; commit the regenerated `00-terraform.yml`; builder returns `blocked` naming the commands
- [ ] 8.3 ⚠ irreversible: Rue runs `bootstrap.yml` for `pihole01`, then `pihole.yml --check`, then `pihole.yml` for real, then again expecting `changed=0`; builder returns `blocked` naming the commands
- [ ] 8.4 Rue verifies from a LAN machine: `dig @192.168.0.225 doubleclick.net` blocked, `dig @192.168.0.225 example.org` resolves, `http://192.168.0.225/admin` accepts the vault password
- [ ] 8.5 ⚠ irreversible: bump `pihole_version` in a PR and merge it (deploys via `runner01`); smoke check passes
