## Context

Life-Manager and Rues-Arcade each keep one SQLite file under `/var/lib/<svc>/`
in their own unprivileged LXC; nothing copies it anywhere. Deploys run from
`runner01` (`deploy.yml`, `--limit proxmox_guest`) and cannot reach `proxmox1`
by design (`docs/deploy-runner.md`). The node is reachable only from the
workstation with the node key (`proxmox_node` group in the rendered
inventory, `ansible_user: root`). The only node-side Ansible so far is
`roles/proxmox_lxc_tun`, which delegates to `{{ proxmox_node_ip }}`.

Proof in this repo is lint + syntax-check + fixture tests under
`scripts/tests/` (no molecule, never a real host). `check01`, where CI runs
proof, has no `sqlite3` binary.

## Goals / Non-Goals

**Goals:** one registry entry per service host drives a pre-deploy snapshot
inside the guest, a nightly collection onto the node (integrity-checked,
rotated, with metadata, alerting via healthchecks.io) and a restore playbook;
every behaviour of the two scripts is provable offline.

**Non-Goals:** see proposal — no encryption, no offsite copy, no vzdump/PBS, no
non-app data, no CI path to the node, no in-app export, no scheduled restore
drill, no monitoring stack.

## Decisions

- **Storage on proxmox1 under `/var/backups/homelab/`, not inside the guests or a backup LXC** — survives LXC recreate without extra containers. Same disk as the guests: accepted (R3), documented as not covered.
- **No encryption, storage on the same server** — Rue: "so deep ist das nicht".
- **Only app DBs** — Rue's choice.
- **Daily + pre-deploy, healthchecks.io for alerting** — Rue's choice (recommended option).
- **Retention 14 daily + 10 pre-deploy** — Rue's choice.
- **Pre-restore snapshots rotate too, newest 10 per service** — Rue at Gate 1. Rotated by `pre-restore` itself after its snapshot was kept, with the same per-stem, name-sorted rule.
- **Live order: before Gate 2 only `--check` runs; real runs after merge** — Rue at Gate 1, same as the pihole01 rebuild. Nothing unmerged lands on a real host.
- **Pre-deploy snapshot on every service playbook run, not only on version change** — deploy-targets only runs changed playbooks, so extra snapshots are rare; simpler than detecting version changes.
- **A failing pre-deploy snapshot blocks the deploy** — no migration without a way back.
- **Rue creates the healthchecks.io check and puts the ping URL into the vault** — it's an external account.
- **Pre-deploy snapshot runs inside the guest, the node collects it nightly (R1)** — CI cannot reach the node, so the deploy path can only write guest-local. A Terraform recreate wipes guest-local pre-deploy snapshots that the node has not copied yet (R2, accepted: copies reach the node within a day).
- **One snapshot implementation, in the guest.** `sqlite-snapshot` (installed by `sqlite_snapshot`) writes snapshot + metadata for all three kinds (`pre-deploy` from Ansible, `daily` and `pre-restore` via `pct exec` from the node). Alternative: the node script drives `sqlite3` through `pct exec` directly — rejected, it would duplicate the metadata logic for the pre-deploy path.
- **Metadata is read from the snapshot, not the live DB**, so it describes exactly what was saved. Release version comes from `<release_link>/.deployed_version` (the marker the service roles write); missing → `unknown`.
- **Node-side Ansible beyond proxmox_lxc_tun is within the boundary (R4)** — `pct exec/pull/push` and a systemd timer are not guest lifecycle; CLAUDE.md's boundary only forbids create/resize/delete via Ansible.
- **Rotation sorts by file name, not mtime.** Names carry a UTC `YYYYmmddTHHMMSSZ` stamp, so lexical order is chronological; deterministic in fixtures and immune to `pct pull` resetting mtimes.
- **Rotation and failure are per service.** A service whose run failed keeps all its old snapshots; the others rotate normally. "A failed run never deletes old snapshots" holds for the failed service, and one broken guest does not stop rotation for the rest.
- **Integrity check on the node, before a file lands in its final dir.** Pulls go to a temp name in the target dir; only `PRAGMA integrity_check` = `ok` renames it into place. A crash mid-run leaves no half file under a real snapshot name.
- **Scripts read a key=value config file, never `source` it**, and call `pct`, `sqlite3`, `curl`, `timeout` through `PATH`. Fixture tests point the config env var at a temp file and put stubs first on `PATH`. Stubs rather than real `sqlite3` because check01 has none (adding it means a hand reconverge of check01 before CI could go green).
- **The node script owns the logic the restore playbook needs to be testable** (`locate`, `pre-restore`); the playbook only sequences stop/push/fix/start/healthz.
- **Restore checks `/healthz` from inside the guest through nginx**, like the service roles' `verify.yml`, with `Host: nginx_server_name | default(default_ipv4 address)` — the service roles' smoke vars are not loaded in a playbook without those roles.
- **Owner/mode are set inside the guest after `pct push` (R5)**, with `ansible.builtin.file` on the guest, not `pct push --user`, because of unprivileged UID mapping.
- **Registry values are literal paths**, not `{{ life_manager_db_path }}`: the node play reads them through `hostvars` without the service role loaded.
- **Mixed guest OS (R6)** — `sqlite3` is packaged on Debian 12 and 13; nothing version-specific is used.
- **No automated "unregistered service" check (R7)** — mitigated by the CLAUDE.md rule only.
- **`ansible-playbook` in fixture tests** (preflight asserts, guest role skip): `--check` against a fixture inventory whose hosts use `ansible_connection: local`, output redirected to a file, never piped (CLAUDE.md learning on "requires blocking IO").

## Contracts

Shared by units 2, 3 and 4. Names are fixed; anything not listed is the builder's choice.

### Registry variable (host_vars of a service host)

```yaml
# --- sqlite backups (roles/sqlite_snapshot, roles/sqlite_backup, 00_OPERATIONAL/sqlite_restore.yml) ---
sqlite_backups:
  service: life-manager                  # label in metadata
  unit: life-manager.service             # stopped/started by restore
  owner: life-manager                    # owner/group/mode set after restore
  group: life-manager
  mode: "0640"                           # optional, default "0640"
  release_link: /opt/life-manager/current  # optional; <link>/.deployed_version → metadata release
  healthz_url: http://127.0.0.1/healthz  # optional, default as shown
  databases:
    - /var/lib/life-manager/life-manager.db
```

Rues-Arcade: same shape with `rues-arcade`, `/opt/rues-arcade/current`,
`/var/lib/rues-arcade/rues-arcade.db`. A host without `sqlite_backups` is
ignored by both roles. Every database path ends in `.db` (both roles assert it) and its basename stem is unique per host.

### Guest side — `roles/sqlite_snapshot`

- Script `/usr/local/sbin/sqlite-snapshot` (source: `ansible/roles/sqlite_snapshot/files/sqlite-snapshot`, plain bash, not a template).
- Config `/etc/sqlite-snapshot.conf`, override path with env `SQLITE_SNAPSHOT_CONF`:
  ```
  SERVICE=life-manager
  RELEASE_LINK=/opt/life-manager/current   # may be empty
  SNAPSHOT_DIR=/var/backups/sqlite-snapshot
  KEEP_PRE_DEPLOY=10
  DATABASE=/var/lib/life-manager/life-manager.db   # one line per DB
  ```
- `sqlite-snapshot <daily|pre-deploy|pre-restore>`: per DATABASE writes
  `$SNAPSHOT_DIR/<kind>/<stem>-<YYYYmmddTHHMMSSZ>.db` via
  `sqlite3 <db> ".backup '<tmp>'"` (busy timeout set), renamed into place when
  complete, plus `<same>.meta`. Prints each written `.db` path, one per line, on
  stdout; messages on stderr.
  - `pre-deploy`: missing DB → stderr `skip: <db> does not exist yet`, exit 0 for that DB. Keeps the newest `KEEP_PRE_DEPLOY` per stem.
  - `daily`, `pre-restore`: missing DB → error, exit non-zero. Keeps only the newest snapshot of that kind per stem (history lives on the node).
  - Any `.backup` failure → exit non-zero, no file left under a snapshot name.
- `sqlite-snapshot list pre-deploy`: prints basenames of existing pre-deploy `.db` snapshots, one per line.
- `.meta` (key=value, one per line, this order; `schema_migration` omitted when the table does not exist):
  ```
  timestamp=2026-10-11T03:30:12Z
  host=life-manager01
  service=life-manager
  database=/var/lib/life-manager/life-manager.db
  kind=daily
  release=v0.2.2            # or: unknown
  user_version=4
  schema_migration=0003_wavelength.sql
  ```
  `schema_migration` = `SELECT name FROM schema_migrations ORDER BY name DESC LIMIT 1`.
- Role vars: `sqlite_snapshot_script`, `sqlite_snapshot_conf`, `sqlite_snapshot_dir` (`/var/backups/sqlite-snapshot`), `sqlite_snapshot_keep_pre_deploy` (10). Tasks: `install.yml` (apt `sqlite3`), `configure.yml` (script 0755, conf 0644), `snapshot.yml` (runs `sqlite-snapshot pre-deploy`, changed when stdout non-empty). Everything is skipped when `sqlite_backups` is undefined.
- Both `02_SERVICES` playbooks list `sqlite_snapshot` directly before their service role.

### Node side — `roles/sqlite_backup`

- Script `/usr/local/sbin/homelab-sqlite-backup` (source: `ansible/roles/sqlite_backup/files/homelab-sqlite-backup`, plain bash).
- Config `/etc/homelab-sqlite-backup.conf` (root, 0600, task with `diff: false`), override with env `HOMELAB_SQLITE_BACKUP_CONF`:
  ```
  BACKUP_ROOT=/var/backups/homelab
  KEEP_DAILY=14
  KEEP_PRE_DEPLOY=10
  KEEP_PRE_RESTORE=10
  PING_URL=https://hc-ping.com/<uuid>
  SNAPSHOT_CMD=/usr/local/sbin/sqlite-snapshot
  GUEST=life-manager01 <lxc_ctid>          # one line per registered host
  ```
- `homelab-sqlite-backup run` (what the timer calls): per GUEST
  1. `pct exec <ctid> -- $SNAPSHOT_CMD daily` → paths; per path `pct pull` the `.db` and `.meta` into `$BACKUP_ROOT/<host>/daily/` (temp name), `sqlite3 <file> 'PRAGMA integrity_check;'` must print exactly `ok`, else both files are deleted and the host fails.
  2. `pct exec <ctid> -- $SNAPSHOT_CMD list pre-deploy` → each name not yet in `$BACKUP_ROOT/<host>/pre-deploy/` is pulled and checked the same way.
  3. Host succeeded → rotate `daily/` to `KEEP_DAILY` and `pre-deploy/` to `KEEP_PRE_DEPLOY` newest per stem (`.db` and `.meta` together). Host failed → delete nothing for it.
  4. Logs `<host>: ok` or `<host>: FAILED (<reason>)`; any non-zero `pct`, `sqlite3` or write is a failure of that host only.
  - After all hosts: all ok → `curl -fsS -m 10 --retry 3 -o /dev/null "$PING_URL"`; otherwise `curl … --data-raw "<one line per failed host with reason>" "$PING_URL/fail"`. A curl failure is logged to stderr and does not change the exit status. Exit 0 iff every host succeeded.
- `homelab-sqlite-backup pre-restore <host> <ctid>`: runs `$SNAPSHOT_CMD pre-restore` in that guest, pulls + checks into `$BACKUP_ROOT/<host>/pre-restore/`, then rotates `pre-restore/` to `KEEP_PRE_RESTORE` newest per stem, prints the kept `.db` basename. Non-zero on any failure, and then deletes nothing. No ping.
- `homelab-sqlite-backup locate <host> <snapshot>`: finds `<snapshot>` (a `.db` basename) under `$BACKUP_ROOT/<host>/{daily,pre-deploy,pre-restore}/`. Found → first line is the absolute path, then the `.meta` content; exit 0. Not found → stderr `not found: <snapshot>` followed by every available `<kind>/<name>`; exit 1.
- systemd: `homelab-sqlite-backup.service` (oneshot, `ExecStart=/usr/local/sbin/homelab-sqlite-backup run`), `homelab-sqlite-backup.timer` (`OnCalendar=` from `sqlite_backup_on_calendar`, `Persistent=true`), timer enabled.
- Role vars: `sqlite_backup_root`, `sqlite_backup_keep_daily` (14), `sqlite_backup_keep_pre_deploy` (10), `sqlite_backup_keep_pre_restore` (10), `sqlite_backup_ping_url` (default `""`, real value in `host_vars/proxmox1/vault.yml`), `sqlite_backup_on_calendar`, `sqlite_backup_snapshot_cmd` (must equal `sqlite_snapshot_script`). Tasks: `preflight.yml` (tag `preflight`: assert ping URL non-empty; collect every inventory host with `sqlite_backups`, assert each has `lxc_ctid` and only `.db` database paths, failing with a message naming the host; print the collected list), `install.yml` (apt `sqlite3`), `configure.yml`, `service.yml`.
- Playbook `ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml`: `hosts: proxmox_node`, applies `sqlite_backup`.

### Restore — `ansible/playbooks/00_OPERATIONAL/sqlite_restore.yml`

- Invocation: `ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_restore.yml -l <host> -e sqlite_restore_snapshot=<name>.db`. `hosts: proxmox_guest`; asserts exactly one host in the play, that it has `sqlite_backups`, and that the snapshot's stem matches one of its `databases`.
- Order: `locate` (delegated to `{{ proxmox_node_ip }}`; print the metadata) → `pre-restore <host> <ctid>` (record the name) → stop `unit` → `pct push <ctid> <node path> <db>` (delegated) → remove `<db>-wal`, `<db>-shm` → set owner/group/mode → start `unit` → `uri` `healthz_url` with retries. Healthz never 200 → fail naming the pre-restore snapshot and the command to restore it.

### Fixture tests and proof wiring

- `scripts/tests/sqlite-snapshot.sh` (guest script, guest role, host_vars, service playbooks) and `scripts/tests/sqlite-backup.sh` (node script, node role preflight, node playbook). Each prints `ok: Scenario: <title>` or `FAIL: Scenario: <title> (…)` per scenario and exits non-zero on any failure. Stubs (`pct`, `sqlite3`, `curl`) are created by the test inside its own temp dir; no fixture state outside `mktemp -d`.
- `scripts/proof.sh` sensors:
  - `sqlite-snapshot fixtures` / code `SQLITE_SNAPSHOT_FIXTURES_FAILED`, when a changed file matches `ansible/roles/sqlite_snapshot/*`, `ansible/playbooks/02_SERVICES/*`, `ansible/inventory/host_vars/*` or `scripts/tests/sqlite-snapshot.sh`.
  - `sqlite-backup fixtures` / code `SQLITE_BACKUP_FIXTURES_FAILED`, when a changed file matches `ansible/roles/sqlite_backup/*`, `ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml` or `scripts/tests/sqlite-backup.sh`.

## Risks / Trade-offs

- [Same physical disk for data and backups] → accepted by Rue; `docs/backups.md` says so under "not covered"; offsite copy is split off.
- [Terraform recreate wipes guest-local pre-deploy snapshots] → accepted; the node copies them within a day.
- [Concurrent deploy restarts the service mid-run] → that host fails, the fail ping names it, the next night retries.
- [A hung `pct exec` stalls the whole job] → each guest call is bounded with `timeout`; a timeout is a failure of that host.
- [Stubs encode assumptions about `pct`/`sqlite3` output] → real behaviour is covered by the post-merge live tasks (unit 6).
- [New services forget to register] → CLAUDE.md rule only, no automated check.
- [Snapshot schema newer than the running release on restore] → not detected; metadata is printed first, healthz is the guard (accepted).
- [Merging deploys both services] → intended: the CI deploy is the first real run on the guests (`sqlite3`, script, first pre-deploy snapshot); the snapshot runs before the service role, so a failure blocks only that deploy.
- [`--check` evidence misses what check mode skips] → `command` tasks (the snapshot itself, `pct`) do not run in check mode; Gate 2 rests on the fixture tests plus the dry runs, the real behaviour is proven after merge (unit 6).

## Migration Plan

Before Gate 2 (evidence, nothing changes on a real host):
1. Rue creates the healthchecks.io check and the vaulted ping URL (committed on this branch).
2. Node playbook with `--check` against proxmox1, from the workstation.
3. Both service playbooks with `--check` against their guests, from the workstation.

After the merge (Ship):
4. Node playbook for real, by hand from the workstation.
5. The merge's CI deploy runs both service playbooks → guest script installed, first pre-deploy snapshots.
6. One manual node-job run → first daily snapshots, pre-deploy copies on the node, success ping.
7. Restore drill on rues-arcade01.

Rollback: disable the timer (`systemctl disable --now homelab-sqlite-backup.timer`); remove `sqlite_snapshot` from the service playbooks. Snapshots on disk are inert.

## Open Questions

- None.
