## Context

`efa9f49` removed pihole01 and its role. The old role (`efa9f49^:ansible/roles/pihole`) ran the unpinned `install.yml` installer from `install.pi-hole.net` with a pre-seeded v5-style `setupVars.conf`, set the password with `pihole -a -p` without `changed_when`, and wrote a `SETUP_INFO.txt` that echoed access details. Its leftovers are the `no-changed-when` and `var-naming[no-role-prefix]` skips in `.ansible-lint`. The repo now provisions guests in Terraform (`lxc_hosts` map) and configures them in Ansible; services deploy through `03_SERVICES` playbooks mapped by `scripts/deploy-targets.sh` on merge.

`scripts/deploy-targets.sh` is already generic: it maps `roles/<role>/**` through the roles a playbook applies, `host_vars/<host>/**` through the hosts it targets and `group_vars/<group>*` through their groups, all read from the inventory. S6 therefore needs fixtures, not (expected) script changes. One catch: `ansible/inventory/00-terraform.yml` is committed and regenerated only by `terraform apply`, so until Rue applies and commits it `hosts: pihole` matches no host. A deploy before that is a no-op (play skipped), not a failure, and `host_vars/pihole01/**` only maps to `pihole.yml` once the host is in the inventory.

## Goals / Non-Goals

**Goals:** a native, pinned Pi-hole v6 on `pihole01`, deployed by the existing merge-to-`main` path, idempotent, with no secret in output.

**Non-Goals:** see proposal; in short, no router change, no Terraform nameserver change, no Tailscale DNS, no backup, no custom lists, no egress firewall, and no apply by the agent.

## Decisions

- **Native install, not Docker** — the repo's app-per-LXC model.
- **Restore the old role from history and modernise** — Rue's pick; keeps the proven task split (`prepare`, `packages`, `install`, `configure`, `service`) and adds `verify`. `info.yml` and `SETUP_INFO.txt.j2` are not restored: the summary echoed access details and `scope.md` lists no such step.
- **Same identity as before** (pihole01, vmid/IP 225, 1 core / 512 MiB / 4 GiB) — Rue's pick; the router needs nothing new.
- **FTL serves the web UI directly, no nginx** — Rue's pick; v6 ships its own web server.
- **Base branch is `main`** — repo convention; `chore/trim-agent-gates` carries an unmerged commit this change does not depend on.
- **Smoke check lives in the role (`verify.yml`)** so the playbook ends with it and manual runs get it too (as `life_manager` does); it uses no vault value. Unlike `life_manager` there is no release layout, so no rollback: a failed check fails the play. A failed check never restarts or reinstalls anything.
- **Pinned version via `pihole_version` in `host_vars/pihole01/vars.yml`** — the bump is a PR changing that one line. Exact install mechanism (pinned installer vs. git tag checkout, `setupVars.conf` vs. `pihole.toml`) is decided by spike S9 in wave 1 and recorded below.
- **Password in `host_vars/pihole01/vault.yml`** as `pihole_password` (inline `!vault |`), created by Rue; the role asserts it is defined and applies it only when it changed.

## Contracts

Shared by the role unit, the playbook/inventory unit and the docs unit (these names are fixed here so the units can run in parallel):

- Inventory: group `pihole`, host `pihole01` (192.168.0.225, vmid 225), generated into `00-terraform.yml` by Terraform.
- Playbook: `ansible/playbooks/03_SERVICES/pihole.yml`, `hosts: pihole`, `become: true`, roles `common` then `pihole`. Nothing targets `github_runner`.
- Role `ansible/roles/pihole`: `tasks/main.yml` imports `prepare`, `packages`, `install`, `service`, `configure`, `verify` in that order.
- Role variables (defaults in `defaults/main.yml`, all prefixed `pihole_`):
  - `pihole_version` — pinned `pi-hole/pi-hole` core tag incl. the `v` (see Spike result: web and FTL follow latest at install time); set in `host_vars/pihole01/vars.yml`, no default that silently floats.
  - `pihole_interface` (`eth0`), `pihole_upstream_dns` (list: `8.8.8.8`, `1.1.1.1`).
  - `pihole_password` — from `host_vars/pihole01/vault.yml`; no default; the role fails with a clear message when undefined.
  - `pihole_smoke_domain` (`example.org`), `pihole_smoke_url` (`http://127.0.0.1/admin/`), `pihole_smoke_retries`, `pihole_smoke_delay`.
- Handler: `pihole_restart_ftl` — the only thing that restarts `pihole-FTL`, notified only by a changed config or a changed install.
- Smoke check: `dig @127.0.0.1 {{ pihole_smoke_domain }}` answers; `GET {{ pihole_smoke_url }}` returns 200 or the v6 login redirect.

## Spike result (S9)

Read in the scratchpad (nothing ran on a host): shallow clone of `pi-hole/pi-hole` at tag `v6.4.3` (commit `f47b8ed`, 2026-07-06), files `automated install/basic-install.sh`, `advanced/Scripts/utils.sh`, `advanced/Templates/pihole-FTL.systemd` / `.service`, `pihole` (the `setpassword` code), `advanced/Scripts/api.sh`. Latest tags by `git ls-remote --tags` on 2026-10-05: core `pi-hole/pi-hole` **v6.4.3**, `pi-hole/FTL` v6.7.1, `pi-hole/web` v6.6. The three components are versioned independently.

1. **Seeded config.** Yes, and a pre-seed is mandatory, not optional. `--unattended` is only honoured when an install already exists (`fresh_install=false`, set by `check_fresh_install` when `/etc/pihole/pihole.toml` or `/etc/pihole/setupVars.conf` exists). A fresh install runs `welcomeDialogs`/`chooseInterface`/`setDNS` through `dialog` regardless of the flag, and it also sets a random password. So the role must write a seed file before the installer. Both formats work: `pihole.toml` is read as is; `setupVars.conf` is migrated by `pihole-FTL migrate v6` (`migrate_dnsmasq_configs`) and moved to `/etc/pihole/migration_backup_v6`. **Decision: seed a minimal `pihole.toml`** (`dns.upstreams`, `dns.interface`) with `force: false`, no `setupVars.conf` (v5 format, extra migration step, the old role's choice). On the non-fresh path the installer skips its own `setFTLConfigValue` block (upstreams, interface, query logging, privacy level, random password), so everything not in the seed is FTL's default and the role converges the rest itself with `pihole-FTL --config <key> <value>` (that is what `setFTLConfigValue` in `utils.sh` calls; `pihole-FTL --config -q <key>` reads). Because FTL rewrites `pihole.toml` (adds defaults, hashes the password), the file must not be a managed `template` that is re-applied every run; it is a one-time seed and the settings are converged through `--config`, compared with `--config -q` before setting. **Unverified:** that FTL accepts a partial `pihole.toml` and fills the defaults (no FTL binary was run). If it rejects it, fall back to the old `setupVars.conf` seed, whose migration path is verified in the installer code.
2. **Version pin.** Not possible through the installer. `basic-install.sh` has no version argument. Whatever copy of it runs, `getGitFiles` clones `pi-hole/pi-hole` (to `/etc/.pihole`) and `pi-hole/web` (to `/var/www/html/admin`) from their default branch and resets to the latest tag (`make_repo`/`update_repo`), and `FTLinstall` downloads `https://github.com/pi-hole/ftl/releases/latest/download/pihole-FTL-<arch>` (sha1 from the same host, no signature). `FTLcheckUpdate` re-downloads whenever the installed FTL tag differs from the latest one, so FTL cannot be held back by pre-placing a binary. `/etc/pihole/ftlbranch` only takes a branch name served from `ftl.pi-hole.net`, not a release tag (tags there: unverified).
3. **Git-tag fallback: needed, and it pins core only.** Clone `pi-hole/pi-hole` at the tag into `/etc/.pihole` *before* running the installer and run `automated install/basic-install.sh` from that checkout: `getGitFiles` then sees a repo and calls `update_repo`, which keeps the checkout and only resets to a tag when the current branch is `master`. A detached HEAD would make `update_repo`'s `git pull` fail and abort the installer, so the checkout needs a local branch whose upstream is itself. Tested in the scratchpad (git only, not the installer): `git checkout -b pihole-pinned <tag>`, `git config branch.pihole-pinned.remote .`, `git config branch.pihole-pinned.merge refs/heads/pihole-pinned`, then `git pull --no-rebase --quiet` exits 0 and the HEAD stays on the tag. Web and FTL still follow "latest" at install time. The bigger design (also `pihole_web_version` and `pihole_ftl_version`, plus bypassing the installer's FTL step) would buy a full pin, but needs a core/web/FTL compatibility matrix I could not verify and a patched installer; not built. Containment instead: the installer runs only when Pi-hole is absent or its core version differs from `pihole_version`, never on a plain converge run, so nothing floats between bumps; Pi-hole has no auto-update unless someone runs `pihole -up`. `verify.yml` also asserts that the installed core version equals `pihole_version` and prints the web and FTL versions.
4. **FTL on :53/:80 in the unprivileged LXC (R5): not verifiable here, expected to work.** The v6.4.3 unit (`pihole-FTL.systemd`) runs as user `pihole` with `AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_NET_ADMIN CAP_SYS_NICE CAP_IPC_LOCK CAP_CHOWN CAP_SYS_TIME`; the SysV script falls back to root if `setcap` fails. Binding :53 and :80 needs only `CAP_NET_BIND_SERVICE`, which unprivileged LXC keeps by default; `CAP_SYS_TIME` is the one an LXC default config drops, and whether systemd then refuses to start the unit is unverified. Evidence that it works is secondhand: the old pihole01 ran the v6 installer in an unprivileged guest with module defaults (scope.md). The smoke check in `verify.yml` is the real test on first deploy. Port 53 conflicts: the installer disables the `systemd-resolved` stub listener itself (`disable_resolved_stublistener`); the Debian 13 template may not ship resolved at all. If the unit fails on the capability line, the remedy is a one-line systemd drop-in clearing `CAP_SYS_TIME` from `AmbientCapabilities`; it is not pre-built because the failure is unconfirmed. Also unverified: Debian 13 as a supported OS (upstream's own CI images are Ubuntu 22/24/26; `v6.4.3` has no OS gate, so `PIHOLE_SKIP_OS_CHECK` from the old role is dead and is not restored).

**Chosen shape (for the role unit):**

- `pihole_version: v6.4.3` in `host_vars/pihole01/vars.yml`; the leading `v` is part of the value because it is the git tag; strip it with `regex_replace('^v', '')` when comparing with the installed version (format of the installed version string unverified).
- `packages.yml`: `git`, `curl`, `ca-certificates` (the role needs `git` before the installer's own dependency step), `dialog` is pulled by the installer.
- `install.yml`, in this order, each block guarded by "Pi-hole absent or installed core version != `pihole_version`" (installed core read from `pihole -v -p` or `/etc/pihole/versions` `CORE_VERSION`; the exact read is for U4 to confirm, unverified):
  1. `ansible.builtin.git` `repo: https://github.com/pi-hole/pi-hole.git`, `dest: /etc/.pihole`, `version: "{{ pihole_version }}"`, full history not needed (`depth: 20` matches the installer's own clone);
  2. pin branch: `git -C /etc/.pihole checkout -B pihole-pinned {{ pihole_version }}` plus the two `git config branch.pihole-pinned.*` lines above (`changed_when` set explicitly);
  3. seed `/etc/pihole/pihole.toml` from a small template with `force: false`, mode `0644`;
  4. `ansible.builtin.command: bash "/etc/.pihole/automated install/basic-install.sh" --unattended` with `creates`/guard as above, `no_log` not needed (no secret in env), `timeout` generous (old role used 900 s).
- `configure.yml`: converge `dns.upstreams` and `dns.interface` with `pihole-FTL --config -q` compare, then `--config` set, `changed_when` from the compare. Password: `pihole setpassword` hashes with a new salt on every call, so it can never be compared by value; compare by logging in instead (`POST http://127.0.0.1/api/auth`, body `{"password": ...}`, `no_log: true`: 200 means unchanged, 401 means set it). `api.sh` uses this endpoint. The `/api/auth` response shape on a wrong password is unverified.
- `pihole_restart_ftl` stays the only restart path (notified by a changed seed or install, or a changed `--config` value).

**Contracts amendment:** no variable added or renamed; `pihole_version` is now defined as the `pi-hole/pi-hole` core tag including the `v` (web and FTL follow latest at install time), and `pihole_upstream_dns`/`pihole_interface` are applied by the seed on first install and by `pihole-FTL --config` afterwards.

## Risks / Trade-offs

- R1 First deploy cuts the LAN's DNS if the router already points at .225 and the box is broken → accepted: Rue applies by hand, S8 documents the router fallback; this change does not make Pi-hole the router's resolver.
- R2 Unpinned installer drifts → spike S9, then `pihole_version`.
- R3 `pihole_password` was unrecoverable with the old vault → Rue creates a new one with `ansible-vault`; the agent only wires the variable.
- R4 `deploy-targets.sh` may not map the new `pihole` group → resolved: it is generic; U3 proves it with fixtures.
- R5 FTL on :80/:53 in an unprivileged LXC → spike S9 (old pihole01 ran unprivileged with module defaults, so expected to work).
- A pre-apply merge deploys nothing (no host in the committed inventory); Rue's order is apply → commit regenerated `00-terraform.yml` → deploy.

## Migration Plan

Rue's rollout, in order: set the router fallback resolver; create `host_vars/pihole01/vault.yml`; `terraform plan` then `apply`; commit the regenerated `00-terraform.yml`; `bootstrap.yml` for the new host; `pihole.yml --check`, then for real, then once more (`changed=0`); verify with `dig`; optionally point the router at .225. Rollback: `terraform destroy -target` of the one guest; the router fallback keeps the LAN resolving.

## Open Questions

- Answered by U1 (see Spike result): pin mechanism and seeded-config format.
