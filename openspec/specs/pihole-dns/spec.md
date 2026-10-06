# pihole-dns Specification

## Purpose
TBD - created by archiving change add-pihole. Update Purpose after archive.
## Requirements
### Requirement: pihole01 is declared in Terraform

`terraform/environments/homelab/hosts.auto.tfvars` SHALL declare `pihole01` in `lxc_hosts` with IPv4 192.168.0.225/24 and no declared vmid (Proxmox assigns it; the live guest keeps 225), group `pihole`, the same Debian 13 `template_file_id` as `runner01`, 1 core, 512 MiB RAM, 512 MiB swap, 4 GiB disk, tags `dns` and `terraform`, started on boot. the IP SHALL be a literal and no vmid SHALL be derived from it, the host SHALL live in the hostname-keyed map (no `count`), and no root password SHALL be set.

#### Scenario: Terraform shows exactly one new guest
- **WHEN** Rue runs `terraform plan` with the `pihole01` entry added
- **THEN** the plan shows one new LXC, `pihole01`, with the declared identity and sizing, and no change to any other host
- **AND** `00-terraform.yml` lists `pihole01` in group `pihole` after apply
- **proof:** manual (`terraform plan`/`apply` need the Proxmox API; Rue runs both)

#### Scenario: IP is a literal and vmid is not derived
- **WHEN** the `pihole01` entry is read
- **THEN** `ipv4 = "192.168.0.225/24"` is a literal and no vmid is derived from it
- **proof:** manual (diff review of `hosts.auto.tfvars`; no sensor distinguishes a literal from a derivation)

#### Scenario: The host is added to the keyed map without count
- **WHEN** the change's Terraform diff is read
- **THEN** only `hosts.auto.tfvars` changes, `pihole01` sits under `lxc_hosts`, and no `count` and no root password attribute is introduced
- **proof:** manual (diff review of `terraform/`)

#### Scenario: Terraform sensors stay green
- **WHEN** `scripts/proof.sh --all` runs with the new entry
- **THEN** `terraform fmt -check`, `terraform validate`, `tflint` and `checkov` pass
- **proof:** proof.sh (`terraform fmt -check -recursive`, `terraform validate`, `tflint`, `checkov`)

### Requirement: The pihole role follows the repo's role conventions

`ansible/roles/pihole` SHALL be restored from `efa9f49^` and modernised: `tasks/main.yml` is an import-only hub with one file per step (`prepare`, `packages`, `install`, `configure`, `service`, `verify`), all modules are FQCN, variables are prefixed `pihole_`, `lineinfile` is not used, and files use the `.yml` extension. Anything carrying the password SHALL use `no_log`.

#### Scenario: The role passes lint and syntax check
- **WHEN** `scripts/proof.sh --all` runs
- **THEN** `ansible-lint` and `ansible-playbook --syntax-check` pass for the role and playbook with no warnings
- **proof:** proof.sh (`ansible-lint`, `ansible-playbook --syntax-check`)

#### Scenario: Re-running on an installed host changes nothing
- **WHEN** the playbook runs a second time against an already installed `pihole01`
- **THEN** the recap shows `changed=0` and `ansible-playbook … --check` reports no changes
- **proof:** manual (needs the real host after `terraform apply`; Rue runs it)

#### Scenario: The installer is skipped when the pinned version is present
- **WHEN** the role runs and the installed Pi-hole version equals `pihole_version`
- **THEN** the install step does not run
- **proof:** manual (needs an installed host; observed in the second real run)

#### Scenario: The password never appears in output
- **WHEN** any task that carries `pihole_password` runs, changed or failed
- **THEN** its output is suppressed by `no_log`
- **proof:** manual (inspect the first real run's output; `no_log` presence is also reviewed in the diff)

### Requirement: Pi-hole v6 is installed natively from a pinned release

The role SHALL install Pi-hole v6 natively (no Docker, no `curl | bash` of an unpinned installer) from the release pinned by `pihole_version`, with upstream resolvers 8.8.8.8 and 1.1.1.1, listening on `eth0` for the LAN only, and FTL as the only web server (no lighttpd). The exact mechanism SHALL be the one spike S9 recorded in `design.md`.

#### Scenario: Spike S9 decides the install shape
- **WHEN** U1 completes
- **THEN** `design.md` "Spike result" states whether the unattended v6 install accepts a pre-seeded config (`setupVars.conf` or `pihole.toml`), whether the version can be pinned without the installer pulling `master`, and whether the git-tag fallback is needed; Contracts are adjusted if the variable set changed
- **proof:** manual (research outcome recorded in prose; real confirmation happens at the first apply)

#### Scenario: A fresh host gets the pinned version
- **WHEN** the playbook runs against a new `pihole01` with `pihole_version` set
- **THEN** that version is installed, FTL answers on port 53 on `eth0`, upstreams are 8.8.8.8 and 1.1.1.1, and no lighttpd is installed
- **proof:** manual (needs the real host; Rue runs the playbook)

#### Scenario: The pinned version is unavailable
- **WHEN** `pihole_version` names a release that cannot be fetched and Pi-hole is already running
- **THEN** the play fails before any change to the running installation
- **proof:** manual (needs an installed host and a deliberately bad pin; run by Rue)

#### Scenario: DNS keeps answering during a re-run
- **WHEN** the role re-runs and no configuration or version changed
- **THEN** `pihole-FTL` is not restarted
- **proof:** manual (needs the real host; the second real run shows no restart)

### Requirement: The web UI is served by FTL and protected by the vault password

FTL SHALL serve the web UI directly on :80, with no nginx role in the playbook. The admin password SHALL come from `host_vars/pihole01/vault.yml` as `pihole_password` (ansible-vault inline `!vault |`) and SHALL be applied only when it changed. When `pihole_password` is undefined the play SHALL fail with a clear message instead of leaving the UI open.

#### Scenario: Admin UI accepts the vault password
- **WHEN** a LAN client opens `http://192.168.0.225/admin` and logs in with the vault password
- **THEN** the login succeeds, and no nginx is installed or configured on the host
- **proof:** manual (needs the real host and the vault file Rue creates)

#### Scenario: An unchanged password is not re-applied
- **WHEN** the role runs and the vault password equals the one already set
- **THEN** the password task reports no change
- **proof:** manual (second real run, `changed=0`)

#### Scenario: Missing password fails the play
- **WHEN** `pihole_password` is undefined
- **THEN** the play fails early with a message naming `pihole_password` and `host_vars/pihole01/vault.yml`, and Pi-hole is left untouched
- **proof:** manual (`--check` against `pihole01` without the vault file; needs the host in the inventory)

### Requirement: pihole.yml deploys the role and ends with a smoke check

`ansible/playbooks/02_SERVICES/pihole.yml` SHALL run `hosts: pihole` with roles `common` then `pihole`. The play SHALL end with a smoke check: `dig @127.0.0.1 example.org` answers, and `GET http://127.0.0.1/admin/` returns 200 or the v6 login redirect. A failed check SHALL fail the play. Nothing in `02_SERVICES` SHALL target `github_runner`, the app role SHALL contain no firewall or runtime install, and the check SHALL NOT need the vault password.

#### Scenario: The playbook has the agreed shape
- **WHEN** `scripts/proof.sh --all` runs
- **THEN** `pihole.yml` passes `--syntax-check` and `ansible-lint`, targets only group `pihole`, and applies `common` then `pihole`
- **proof:** proof.sh (`ansible-playbook --syntax-check`, `ansible-lint`)

#### Scenario: A failing smoke check fails the play
- **WHEN** DNS does not answer or the admin URL returns neither 200 nor the login redirect after the configured retries
- **THEN** the play fails and says which check failed
- **proof:** manual (needs a real host with FTL stopped; Rue can try it, not part of Done)

#### Scenario: The smoke check runs without the vault
- **WHEN** the smoke check runs
- **THEN** it uses neither `pihole_password` nor any vaulted value
- **proof:** manual (diff review of `tasks/verify.yml`)

#### Scenario: No host-level concern lives in the app role
- **WHEN** the role and playbook are read
- **THEN** no firewall or runtime install is in the `pihole` role, and no task targets `github_runner`
- **proof:** manual (diff review; the existing CD spec forbids `github_runner` targets in `02_SERVICES`)

### Requirement: The deploy path maps pihole changes to pihole.yml

`scripts/deploy-targets.sh` SHALL map a diff in `roles/pihole/**`, `playbooks/02_SERVICES/pihole.yml`, `inventory/group_vars/pihole*` or `host_vars/pihole01/**` to `pihole.yml`, covered by fixtures in `scripts/tests/deploy-targets.sh`. A diff only under `terraform/` SHALL trigger no playbook, and a diff touching two services SHALL run both.

#### Scenario: Role change runs only the pihole playbook
- **WHEN** a diff changes a file under `ansible/roles/pihole/`
- **THEN** only `02_SERVICES/pihole.yml` is printed
- **proof:** fixture ("Scenario: Role change runs only the pihole playbook")

#### Scenario: Version bump runs only the pihole playbook
- **WHEN** a diff changes `ansible/inventory/host_vars/pihole01/vars.yml`
- **THEN** only `02_SERVICES/pihole.yml` is printed
- **proof:** fixture ("Scenario: Version bump runs only the pihole playbook")

#### Scenario: Group vars of the pihole group run the pihole playbook
- **WHEN** a diff changes `ansible/inventory/group_vars/pihole.yml`
- **THEN** only `02_SERVICES/pihole.yml` is printed
- **proof:** fixture ("Scenario: Group vars of the pihole group run the pihole playbook")

#### Scenario: A terraform-only diff deploys nothing
- **WHEN** a diff changes only files under `terraform/` (e.g. `hosts.auto.tfvars`)
- **THEN** no playbook is printed
- **proof:** fixture ("Scenario: A terraform-only diff deploys nothing")

#### Scenario: A diff touching two services runs both
- **WHEN** a diff changes `host_vars/pihole01/vars.yml` and `host_vars/life-manager01/vars.yml`
- **THEN** both `pihole.yml` and `life-manager.yml` are printed
- **proof:** fixture ("Scenario: A diff touching two services runs both")

### Requirement: Stale pihole skips in .ansible-lint are reviewed

Each pihole-related skip comment in `.ansible-lint` (`no-changed-when`, `var-naming[no-role-prefix]`) SHALL be dropped where the new role no longer needs it, or kept with a reason that is true of the new role. `scripts/proof.sh --all` SHALL be green.

#### Scenario: Skips match the new role
- **WHEN** `ansible-lint` runs with the pihole skip entries removed
- **THEN** every entry that still fails is kept with a comment naming the current reason, and every entry that passes is deleted; no comment mentions the old role's behaviour
- **proof:** proof.sh (`ansible-lint`)

#### Scenario: The whole repo proof is green
- **WHEN** `scripts/proof.sh --all` runs on the branch
- **THEN** it exits 0
- **proof:** proof.sh (`scripts/proof.sh --all`)

### Requirement: Pi-hole is documented, including the DNS-outage risk

`docs/pihole.md` SHALL describe what it is, how to create it and rebuild it through the runner flow (merge, plan, `infrastructure` approval, apply, `pihole.yml` with its smoke check), how to bump the version and how to recover. Its status line SHALL NOT call `pihole01` retired or undeclared. It SHALL state the DNS-outage risk and the router-fallback step even though that step is a Non-Goal of the automation, and the pre-merge check that runner01's `known_hosts` holds no entry for `192.168.0.225`. `terraform/README.md` SHALL no longer describe pihole01 as removed or gone; `docs/tailscale-subnet-router.md` only shows pihole01 as a host behind the router and needs no change.

#### Scenario: The doc covers the runner flow, bump and recovery
- **WHEN** `docs/pihole.md` is read
- **THEN** it describes creation and rebuild as the runner flow with no workstation `terraform apply`, `fetch-inventory.sh` or `bootstrap.yml` step, plus the version-bump PR and the recovery path
- **proof:** manual (prose; no sensor)

#### Scenario: The outage risk and router fallback are stated
- **WHEN** `docs/pihole.md` is read
- **THEN** it states that the LAN loses DNS if the router points at .225 and the box is down, and names the router fallback-resolver step as manual
- **proof:** manual (prose; no sensor)

#### Scenario: The known_hosts pre-check is stated
- **WHEN** `docs/pihole.md` is read
- **THEN** it says to check `ssh-keygen -F 192.168.0.225` on runner01 before merging a rebuild and to remove a stale entry
- **proof:** manual (prose; no sensor)

#### Scenario: Stale "removed" mentions are corrected
- **WHEN** `terraform/README.md` and the status line of `docs/pihole.md` are read
- **THEN** pihole01 is described as present again (one paragraph of correction, not a rewrite)
- **proof:** manual (prose; no sensor)

