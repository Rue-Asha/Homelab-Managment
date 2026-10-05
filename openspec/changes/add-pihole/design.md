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
- Role `ansible/roles/pihole`: `tasks/main.yml` imports `prepare`, `packages`, `install`, `configure`, `service`, `verify` in that order.
- Role variables (defaults in `defaults/main.yml`, all prefixed `pihole_`):
  - `pihole_version` — pinned Pi-hole release/tag; set in `host_vars/pihole01/vars.yml`, no default that silently floats.
  - `pihole_interface` (`eth0`), `pihole_upstream_dns` (list: `8.8.8.8`, `1.1.1.1`).
  - `pihole_password` — from `host_vars/pihole01/vault.yml`; no default; the role fails with a clear message when undefined.
  - `pihole_smoke_domain` (`example.org`), `pihole_smoke_url` (`http://127.0.0.1/admin/`), `pihole_smoke_retries`, `pihole_smoke_delay`.
- Handler: `pihole_restart_ftl` — the only thing that restarts `pihole-FTL`, notified only by a changed config or a changed install.
- Smoke check: `dig @127.0.0.1 {{ pihole_smoke_domain }}` answers; `GET {{ pihole_smoke_url }}` returns 200 or the v6 login redirect.

## Spike result (S9)

_To be written by U1. It must answer: (1) does the v6 unattended install accept a pre-seeded config (`setupVars.conf` vs `pihole.toml`)? (2) can the version be pinned without the installer pulling `master`? (3) is the fallback (pin the `pi-hole/pi-hole` git tag and run `automated install/basic-install.sh` from the checkout) needed? (4) does FTL bind :53 and :80 in the unprivileged LXC (R5)? Then adjust `Contracts` if the variable set changes._

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
