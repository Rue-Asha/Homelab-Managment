## Why

Rue's self-hosted web services (today Life-Manager and Rues-Arcade, later more) keep all their data in one SQLite file per guest, and nothing backs it up. A bad migration, a broken deploy, an accidental delete or a Terraform recreate of the LXC loses data that cannot be rebuilt (Life-Manager is all user data; Arcade's imposter/wavelength content exists nowhere else).

**Appetite:** two sessions.

## What Changes

- **Service registry (S7):** one inventory variable per service host, `sqlite_backups` (DB path(s), systemd unit, owner), is the single source for the guest role, the node role and the restore playbook. Life-Manager and Rues-Arcade are registered.
- **Guest-side role `sqlite_snapshot` (S1, S2):** installs the `sqlite3` CLI and a snapshot script; every run of a service playbook writes a WAL-safe `sqlite3 .backup` snapshot of each registered DB to a pre-deploy dir on the guest *before* the service role runs, keeps the newest 10, and fails the play if the snapshot fails. Every snapshot carries metadata (UTC timestamp, service, release version, `PRAGMA user_version`, newest `schema_migrations.name`).
- **Node-side role `sqlite_backup` on proxmox1 (S3–S6):** a script plus a daily systemd timer that, per registered guest, takes a snapshot inside the guest via `pct exec`, pulls it with `pct pull` to `/var/backups/homelab/<host>/daily/`, copies new pre-deploy snapshots to `/var/backups/homelab/<host>/pre-deploy/`, keeps only snapshots that pass `PRAGMA integrity_check`, rotates to 14 daily / 10 pre-deploy / 10 pre-restore after a successful run, and pings healthchecks.io (success, or fail naming the failed services). The ping URL lives in ansible-vault (`host_vars/proxmox1/vault.yml`).
- **Playbooks in `00_OPERATIONAL/` (S8, S9):** one applies the node role to proxmox1 (by hand from the workstation; CI cannot reach the node), one restores a named snapshot into a service guest: metadata first, current DB saved as `pre-restore`, unit stopped, snapshot pushed, stale `-wal`/`-shm` removed, owner/mode set, unit started, `/healthz` must answer 200.
- **Both service playbooks** (`02_SERVICES/life-manager.yml`, `rues-arcade.yml`) apply `sqlite_snapshot` right before their service role.
- **Docs (S10):** role READMEs, `docs/backups.md` (what, where, retention, restore, onboarding, what is not covered), and a rule in `.claude/CLAUDE.md`: a service with persistent data must be registered.
- **Proof:** offline fixture tests for both scripts under `scripts/tests/`, wired into `scripts/proof.sh`.

## Non-Goals

- Encryption of snapshots — Rue's call: not sensitive enough to justify it.
- Offsite / second-disk copy — Rue's call: same home server is enough; disk failure of proxmox1 is NOT covered (split off as a later change).
- vzdump / whole-LXC images, Proxmox Backup Server — guests are rebuilt from Terraform + Ansible; only data matters.
- Backing up pihole01, runner01 (Terraform state, vault_pass) or the workstation — Rue chose app DBs only.
- CI applying the node playbook or reaching proxmox1 — keeps the deploy-runner boundary (`docs/deploy-runner.md`: no SSH from runner01 to the node).
- In-app export/import endpoints — the apps have no auth; host-level snapshots cover the need.
- Automatic full restore drills — integrity_check every night plus the restore playbook's healthz check; a scheduled restore test can come later.
- A monitoring stack (uptime-kuma, ntfy) — healthchecks.io covers "backup missing or failing".

## Done criteria

- [ ] `scripts/proof.sh --all` is green with both new roles and both new playbooks.
- [ ] After the post-merge live apply: `/var/backups/homelab/{life-manager01,rues-arcade01}/daily/` on proxmox1 holds a snapshot that passes integrity_check, with metadata, and healthchecks.io shows a success ping.
- [ ] A deploy of either service leaves a pre-deploy snapshot that shows up on the node after the next run.
- [ ] A restore of a Rues-Arcade snapshot via the restore playbook ends with /healthz 200 and the content visible in the app.
- [ ] `docs/backups.md` explains onboarding a new service in a few steps.

## Capabilities

### New Capabilities
- `sqlite-backups`: registry of service databases, guest-side pre-deploy snapshots with metadata, nightly node-side collection with integrity check, rotation and healthchecks.io ping, the node and restore playbooks, and the backup docs.

### Modified Capabilities
<!-- none: the deploy path is unchanged; the service playbooks gain one role that continuous-deployment already covers (role changes map to the playbooks using them). -->

## Impact

- New: `ansible/roles/sqlite_snapshot/`, `ansible/roles/sqlite_backup/`, `ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml`, `ansible/playbooks/00_OPERATIONAL/sqlite_restore.yml`, `ansible/inventory/host_vars/proxmox1/vault.yml` (added by Rue), `docs/backups.md`, `scripts/tests/sqlite-snapshot.sh`, `scripts/tests/sqlite-backup.sh`.
- Changed: `ansible/playbooks/02_SERVICES/{life-manager,rues-arcade}.yml`, `ansible/inventory/host_vars/{life-manager01,rues-arcade01}/vars.yml`, `scripts/proof.sh`, `.claude/CLAUDE.md`.
- Live order (Rue at Gate 1): before Gate 2 only `--check` runs are evidence; nothing unmerged lands on a real host. After the merge: the node playbook by hand, the services via the CI deploy (their host_vars and playbooks change, so the merge runs both: `sqlite3` on both guests, first pre-deploy snapshot), then one manual node-job run and the restore drill.
- proxmox1 gains a systemd timer, a script, `sqlite3`, and `/var/backups/homelab/` on the same disk as the guests (risk accepted, documented).
- External: a healthchecks.io check owned by Rue.
