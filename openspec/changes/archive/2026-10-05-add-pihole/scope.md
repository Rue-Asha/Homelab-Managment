# Scope: add-pihole

Triage: feature — new guest, new role and playbook, LAN-wide DNS. Appetite: two evenings.

## Problem
Rue's LAN has no ad-blocking DNS resolver since `efa9f49` removed pihole01 together with the
other pre-rebuild services. It ran as a native Pi-hole on a Proxmox LXC; the Terraform/Ansible
rebuild has no replacement yet.

## Flows
- Provision: add `pihole01` to `hosts.auto.tfvars` → `terraform apply` (Rue, by hand) → `00-terraform.yml` lists the host in group `pihole`.
- Configure: merge to `main` touching the pihole role/playbook/vars → `deploy-targets.sh` maps the diff to `03_SERVICES/pihole.yml` → runner01 runs it → smoke check passes.
- Use: LAN client asks 192.168.0.225:53 → Pi-hole answers or blocks → admin opens `http://192.168.0.225/admin` and logs in.
- Bump: PR changes the pinned Pi-hole version in host vars → merge → playbook converges to that version.

## In scope
- **S1** `terraform/environments/homelab/hosts.auto.tfvars` declares `pihole01`: vmid 225, 192.168.0.225/24, group `pihole`, Debian 13 `template_file_id` as runner01, 1 core / 512 MiB RAM / 512 MiB swap / 4 GiB disk, tags `dns` and `terraform`, started on boot.
  - edges: vmid and IP are independent declarations (no derivation); `for_each` over the hostname map, no `count`; no root password; `terraform fmt -check`, `validate`, `tflint` and `checkov` stay green.
- **S2** Role `ansible/roles/pihole`, restored from `efa9f49^` and modernised: `tasks/main.yml` is import-only, one file per step (`prepare`, `packages`, `install`, `configure`, `service`, `verify`), FQCN, role-prefixed vars, no `lineinfile`, `.yml` only.
  - edges: re-running on an already installed host changes nothing (idempotent, ansible-lint `--check` shows no changes after the first run); installer is skipped when the pinned version is already present; `no_log` on anything carrying the password.
- **S3** Pi-hole v6 is installed natively from a pinned release (no `curl | bash` of an unpinned installer, no Docker), upstream resolvers 8.8.8.8 and 1.1.1.1, listening on eth0 for the LAN only, FTL as the only web server (no lighttpd).
  - edges: pinned version unavailable → play fails before touching a running installation; DNS keeps answering while the role re-runs (FTL is not restarted when nothing changed).
- **S4** Web UI served by FTL directly on :80 (no nginx role in the playbook); admin password comes from `host_vars/pihole01/vault.yml` (`pihole_password`, ansible-vault inline `!vault |`) and is applied only when it changed.
  - edges: `pihole_password` undefined → play fails with a clear message instead of leaving the UI open; the password never shows up in play output or logs.
- **S5** `ansible/playbooks/03_SERVICES/pihole.yml` runs `hosts: pihole` with roles `common` then `pihole` and ends with a smoke check: `dig @127.0.0.1 example.org` answers, and `GET http://127.0.0.1/admin/` returns 200 (or the v6 login redirect). A failed check fails the play.
  - edges: nothing targets `github_runner`; no firewall or runtime install inside the app role; the check does not need the vault password.
- **S6** The deploy path covers it: `scripts/deploy-targets.sh` maps a diff in `roles/pihole/**`, `playbooks/03_SERVICES/pihole.yml`, `inventory/group_vars/pihole*` or `host_vars/pihole01/**` to `pihole.yml`, with a fixture test in `scripts/tests/deploy-targets.sh`.
  - edges: a diff only under `terraform/` triggers no playbook; a diff touching two services runs both.
- **S7** `.ansible-lint` stale pihole skip comments are reviewed: dropped where the new role no longer needs them, kept with a reason where it does. `scripts/proof.sh --all` is green.
  - edges: none (housekeeping tied to the role coming back).
- **S8** Docs: `docs/pihole.md` (what it is, how to apply the first time, how to bump the version, how to recover) and a one-paragraph correction in `terraform/README.md` / `docs/tailscale-subnet-router.md` where pihole01 is mentioned as removed.
  - edges: the doc states the DNS-outage risk and the router-fallback step even though that step is a Non-Goal of the automation.
- **S9** spike: does Pi-hole v6's unattended install accept a pre-seeded config (`setupVars.conf` vs. `pihole.toml`) and a pinnable version without the installer pulling `master`? → decides the exact shape of S2/S3 in wave 1. If it cannot be pinned, fall back to pinning the git tag of `pi-hole/pi-hole` and running its `automated install/basic-install.sh` from the checkout.

## Non-goals
- Pointing the router's DHCP at .225 — manual router change; the router fallback resolver is documented (S8), not automated.
- Terraform `network_nameservers` pointing at Pi-hole — would make runner01/life-manager depend on one DNS box. Later.
- Tailscale DNS / Pi-hole over the VPN (`tailscale_accept_dns` stays `false`).
- Backup/restore of Pi-hole config and gravity DB, a second Pi-hole, or Gravity Sync.
- Custom blocklists, local DNS records, DHCP server on the Pi-hole: defaults only.
- `egress_firewall` on pihole01 — it ran without it before, and its default-drop egress needs a DNS-upstream design.
- Running `terraform apply` or the playbook from the agent. Both stay Rue's decision.

## Codebase touchpoints
- `terraform/environments/homelab/hosts.auto.tfvars` — new `pihole01` entry (explorer: current state; .225/vmid 225 free)
- `ansible/roles/pihole/**` — restored from `efa9f49^`, rewritten to current conventions (explorer: old role layout)
- `ansible/playbooks/03_SERVICES/pihole.yml` — new (explorer: old playbook was `common` + `pihole`)
- `ansible/inventory/host_vars/pihole01/{vars,vault}.yml` — new; `00-terraform.yml` is generated, never edited (explorer: vault convention)
- `scripts/deploy-targets.sh`, `scripts/tests/deploy-targets.sh` — mapping + fixtures (to be read by the planner)
- `.ansible-lint` lines ~20–26 — stale pihole skips (explorer)
- `docs/pihole.md`, `terraform/README.md`, `docs/tailscale-subnet-router.md` — docs

## Risks
- R1 First deploy cuts the LAN's DNS if the router already points at .225 and the box is broken → accepted: Rue applies by hand, and S8 documents the router fallback; Pi-hole is not made the router's resolver by this change.
- R2 Unpinned installer drifts → spike S9.
- R3 `pihole_password` was unrecoverable with the old vault; a new one has to be created with `ansible-vault` by Rue → accepted: the vault file is created by Rue (secret), the agent only wires the variable.
- R4 `deploy-targets.sh` may not yet map a new `pihole` group generically → resolved in S6 by the planner reading the script and its fixtures.
- R5 FTL on :80 in an unprivileged LXC needs `CAP_NET_BIND_SERVICE` / port 53 binding → spike S9 (old pihole01 ran unprivileged with the module defaults, so expected to work).

## Decisions
- Native install, not Docker — repo's app-per-LXC model.
- Restore the old role from history and modernise — Rue's pick; keeps the proven task split.
- Same identity as before (pihole01, vmid/IP 225, 1 core/512 MiB/4 GiB) — Rue's pick; the router needs nothing new.
- FTL serves the web UI directly, no nginx — Rue's pick; v6 ships its own web server, an extra proxy buys nothing here.
- Base branch is `main` — repo convention is cutting from `main`; `chore/trim-agent-gates` carries an unmerged commit (`2ac5ed9`) that this change does not depend on.

## Done when
- `scripts/proof.sh --all` is green on the branch and CI is green on the PR.
- `terraform plan` (Rue runs it) shows exactly one new LXC, `pihole01`.
- `ansible-playbook … pihole.yml --check` runs clean, and a second real run reports `changed=0`.
- From a LAN machine: `dig @192.168.0.225 doubleclick.net` returns a block answer and `dig @192.168.0.225 example.org` resolves; `http://192.168.0.225/admin` accepts the vault password.
- Bumping the pinned version via PR deploys on merge and the smoke check passes.

## Split off
- Terraform `network_nameservers` → Pi-hole, with a fallback resolver — later change.
- Tailscale DNS through Pi-hole — later change.
- Backup/restore of Pi-hole state — later change.
