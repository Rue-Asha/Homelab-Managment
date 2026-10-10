# Scope: sqlite-backups

Triage: feature + live — new backup capability for every service guest plus a node-side job on proxmox1; first apply on real hosts. Appetite: two sessions.

## Problem
Rue's self-hosted web services (today Life-Manager and Rues-Arcade, later more) keep all their data in one SQLite file per guest, and nothing backs it up. A bad migration, a broken deploy, an accidental delete or a Terraform recreate of the LXC loses data that cannot be rebuilt (Life-Manager is all user data; Arcade's imposter/wavelength content exists nowhere else).

## Flows
- Nightly: systemd timer on proxmox1 → for each registered service guest: consistent SQLite snapshot inside the guest → pulled to the node → integrity-checked → stored with metadata → old ones rotated → one healthchecks.io ping (success, or fail naming the services that failed).
- Deploy: CI (runner01) runs the service's 02_SERVICES playbook against the guest → before the service role installs/starts a release, a guest-side snapshot is written to the guest's pre-deploy dir → deploy continues → the next nightly run copies new pre-deploy snapshots to the node.
- Restore: Rue runs a 00_OPERATIONAL restore playbook from the workstation, naming service + snapshot → current DB saved as a pre-restore snapshot → service stopped → snapshot pushed in, -wal/-shm removed, ownership fixed → service started → /healthz must answer 200.
- Onboarding a future service: set one inventory variable on its host (DB path, service unit, owner), add the guest-side role to its playbook, re-run the node playbook by hand → the service is in the nightly run.

## In scope
- **S1** A guest-side role installs the `sqlite3` CLI and, when the service playbook runs, writes a consistent snapshot of each registered DB (`sqlite3 .backup`, WAL-safe) to a pre-deploy dir on the guest before the service role runs; keeps the newest 10.
  - edges: DB file does not exist yet (first deploy) → skip with a message, deploy continues | snapshot command fails → playbook fails before the release changes (no deploy without a snapshot) | playbook run without a version change → still snapshots (accepted, see Decisions)
- **S2** Every snapshot (daily and pre-deploy) carries metadata: UTC timestamp, service, app release version, and the schema marker (`PRAGMA user_version`, plus the newest `schema_migrations.name` when that table exists).
  - edges: DB without `schema_migrations` table → only user_version recorded | release version unknown (no `current` symlink) → recorded as `unknown`, not a failure
- **S3** A node-side role on proxmox1 installs a script + systemd timer (daily) that, per registered service guest, runs the snapshot inside the guest via `pct exec`, pulls it with `pct pull` to `/var/backups/homelab/<host>/daily/`, and also copies any pre-deploy snapshots the node doesn't have yet to `/var/backups/homelab/<host>/pre-deploy/`.
  - edges: guest stopped / pct exec fails → that service is marked failed, the others still run | registered DB missing in the guest → failed (abnormal after first deploy) | concurrent deploy restarts the service mid-run → that snapshot fails, reported, next night retries | node disk full → failed
- **S4** Each pulled snapshot passes `PRAGMA integrity_check` on the node before it is kept; a failing one is deleted and the service marked failed.
  - edges: none (binary outcome, covered by S3 failure path)
- **S5** Rotation on the node: newest 14 daily and newest 10 pre-deploy snapshots per service; older ones deleted after a successful run.
  - edges: a failed run never deletes old snapshots | fewer than 14 present → nothing deleted
- **S6** The node job pings healthchecks.io: success ping when every service succeeded, fail ping (body lists failed services) otherwise. Ping URL lives in ansible-vault (`host_vars/proxmox1/vault.yml`).
  - edges: ping URL unset → node playbook assert fails at apply time | healthchecks.io unreachable → logged, job exit status still reflects the backup result | job never runs (timer broken, node down) → healthchecks.io alerts on the missing ping (grace configured there by Rue)
- **S7** Service registry: one inventory variable per service host (DB path(s), systemd unit, owner) is the single source for S1, S3 and S8. Life-Manager and Rues-Arcade are registered; both service playbooks include the guest-side role.
  - edges: host without the variable → ignored by both roles | variable present but guest not in `proxmox_guest` (no lxc_ctid) → node playbook fails with a clear message
- **S8** Restore playbook in `ansible/playbooks/00_OPERATIONAL/`, run from the workstation with the node key: takes service host + snapshot name, prints the snapshot's metadata, saves the current DB as a `pre-restore` snapshot on the node, stops the unit, pushes the snapshot in, removes stale -wal/-shm, sets owner/mode, starts the unit, waits for /healthz 200.
  - edges: snapshot name not found → fails listing available snapshots | /healthz not 200 after restore → playbook fails and names the pre-restore snapshot to roll back with | snapshot schema newer than the running release → not detected automatically; metadata shown first, healthz is the guard (accepted)
- **S9** A playbook in `00_OPERATIONAL/` applies the node-side role to proxmox1 (run by hand from the workstation; CI can't reach the node by design).
  - edges: run with `--check` → no changes, shows what would be installed
- **S10** Docs: role READMEs, a `docs/backups.md` (what is backed up, where, retention, restore steps, how to onboard a service, what is NOT covered), and a rule in `.claude/CLAUDE.md` service-delivery section: a service with persistent data must be registered in the backup registry.
  - edges: none (documentation)

## Non-goals
- Encryption of snapshots — Rue's call: not sensitive enough to justify it.
- Offsite / second-disk copy — Rue's call: same home server is enough; disk failure of proxmox1 is NOT covered (see Split off).
- vzdump / whole-LXC images, Proxmox Backup Server — guests are rebuilt from Terraform + Ansible; only data matters.
- Backing up pihole01, runner01 (Terraform state, vault_pass) or the workstation — Rue chose app DBs only.
- CI applying the node playbook or reaching proxmox1 — keeps the deploy-runner boundary (docs/deploy-runner.md: no SSH from runner01 to the node).
- In-app export/import endpoints — the apps have no auth; host-level snapshots cover the need.
- Automatic full restore drills — integrity_check every night plus the restore playbook's healthz check; a scheduled restore test can come later.
- A monitoring stack (uptime-kuma, ntfy) — healthchecks.io covers "backup missing or failing".

## Codebase touchpoints
- `ansible/roles/<new guest-side role>/` — sqlite3 install + pre-deploy snapshot (explorer: no sqlite3 in common/nodejs/template)
- `ansible/roles/<new node-side role>/` — script, systemd service+timer, rotation, ping; modeled on `roles/proxmox_lxc_tun` node delegation (explorer: only node-managed config so far)
- `ansible/playbooks/02_SERVICES/life-manager.yml`, `rues-arcade.yml` — add guest-side role before the service role (explorer: roles list common, nodejs, nginx, <svc>)
- `ansible/playbooks/00_OPERATIONAL/` — node playbook + restore playbook (explorer: dir is empty, documented for backups)
- `ansible/inventory/host_vars/life-manager01/vars.yml`, `rues-arcade01/vars.yml` — registry variable; DB paths `/var/lib/life-manager/life-manager.db`, `/var/lib/rues-arcade/rues-arcade.db` (explorer: roles/*/defaults/main.yml)
- `ansible/inventory/host_vars/proxmox1/vault.yml` — healthchecks ping URL (explorer: pihole01 vault.yml is the precedent)
- `docs/backups.md`, `.claude/CLAUDE.md` — docs + onboarding rule
- `scripts/proof.sh` — new playbooks get syntax-check automatically; a node script gets a test with fixtures under `scripts/tests/` (explorer: no molecule, lint + syntax-check only)

## Risks
- R1 CI can't reach proxmox1, so a pre-deploy snapshot can't be node-side → resolved: pre-deploy snapshot runs inside the guest (S1), node collects it nightly (S3).
- R2 Terraform recreate wipes guest-local pre-deploy snapshots → accepted: copies reach the node within a day; daily snapshots live only on the node.
- R3 Same physical disk for data and backups → accepted by Rue; documented in docs/backups.md as not covered.
- R4 Node-side Ansible beyond proxmox_lxc_tun → resolved: `pct exec/pull` and a systemd timer are not guest lifecycle; CLAUDE.md's boundary only forbids create/resize/delete via Ansible.
- R5 Unprivileged LXC file ownership on restore → resolved in S8 by explicitly setting owner/mode inside the guest after `pct push`.
- R6 Mixed guest OS (one guest on Debian 12) → accepted: `sqlite3` package exists on both.
- R7 New services forget to register → mitigated by the CLAUDE.md rule (S10); no automated check.

## Decisions
- No encryption, storage on the same server — Rue: "so deep ist das nicht".
- Storage on proxmox1 under `/var/backups/homelab/`, not inside the guests or a backup LXC — survives LXC recreate without extra containers.
- Only app DBs — Rue's choice.
- Daily + pre-deploy, healthchecks.io for alerting — Rue's choice (recommended option).
- Retention 14 daily + 10 pre-deploy — Rue's choice.
- Pre-deploy snapshot on every service playbook run, not only on version change — deploy-targets only runs changed playbooks, so extra snapshots are rare; simpler than detecting version changes.
- A failing pre-deploy snapshot blocks the deploy — no migration without a way back.
- Rue creates the healthchecks.io check and puts the ping URL into the vault — it's an external account.

## Done when
- `proof.sh --all` is green with both new roles and both new playbooks.
- After the live apply: `/var/backups/homelab/{life-manager01,rues-arcade01}/daily/` on proxmox1 holds a snapshot that passes integrity_check, with metadata, and healthchecks.io shows a success ping.
- A deploy of either service leaves a pre-deploy snapshot that shows up on the node after the next run.
- A restore of a Rues-Arcade snapshot via the restore playbook ends with /healthz 200 and the content visible in the app.
- docs/backups.md explains onboarding a new service in a few steps.

## Split off
- Copy of `/var/backups/homelab/` to the workstation or a second disk (protects against disk failure) — later change if wanted.
