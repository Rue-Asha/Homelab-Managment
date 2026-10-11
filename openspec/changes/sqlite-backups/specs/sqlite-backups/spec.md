## ADDED Requirements

### Requirement: One registry entry per service host drives every backup step

Each service host whose service keeps a SQLite database SHALL declare one inventory variable, `sqlite_backups`, holding its database path(s), systemd unit and owner, and this variable SHALL be the single source the guest-side role, the node-side role and the restore playbook read. Life-Manager (`life-manager01`) and Rues-Arcade (`rues-arcade01`) SHALL be registered. A host without the variable SHALL be ignored by both roles. A host that has the variable but no `lxc_ctid` SHALL make the node playbook fail with a message naming that host.

#### Scenario: Life-Manager and Rues-Arcade are registered
- **WHEN** `host_vars/life-manager01/vars.yml` and `host_vars/rues-arcade01/vars.yml` are read
- **THEN** each defines `sqlite_backups` with unit, owner and the literal database path `/var/lib/life-manager/life-manager.db` resp. `/var/lib/rues-arcade/rues-arcade.db`
- **proof:** unit

#### Scenario: Guest role skips a host without a registry entry
- **WHEN** `sqlite_snapshot` is applied to a host that has no `sqlite_backups`
- **THEN** no task of the role runs (no package, no script, no snapshot) and the play succeeds
- **proof:** unit

#### Scenario: Node playbook ignores a host without a registry entry
- **WHEN** the node playbook's preflight runs against an inventory where one guest has `sqlite_backups` and another has none
- **THEN** only the registered guest is listed for the nightly job and the preflight succeeds
- **proof:** unit

#### Scenario: Registered host without a container ID
- **WHEN** a host has `sqlite_backups` but no `lxc_ctid` (not an LXC in `proxmox_guest`) and the node playbook runs
- **THEN** the play fails before changing anything, with a message naming that host
- **proof:** unit

#### Scenario: Registered database path without .db suffix
- **WHEN** a host registers a database path that does not end in `.db` and the node playbook runs
- **THEN** the play fails in preflight before anything is installed, with a message naming that host and `.db`
- **proof:** unit

#### Scenario: Role rejects a database path without .db suffix
- **WHEN** `sqlite_snapshot` is applied to a host whose registered database path does not end in `.db`
- **THEN** the role fails before any snapshot is taken, with a message naming the path
- **proof:** unit

### Requirement: Service playbooks snapshot the database before the service role runs

The guest-side role `sqlite_snapshot` SHALL install the `sqlite3` CLI and, on every run of a service playbook, SHALL write a consistent `sqlite3 .backup` (WAL-safe) snapshot of each registered database to a pre-deploy directory on the guest before the service role runs, keeping the newest 10 per database. If a snapshot fails the play SHALL fail before the release changes. A database that does not exist yet SHALL be skipped with a message.

#### Scenario: Pre-deploy snapshot is written
- **WHEN** `sqlite-snapshot pre-deploy` runs on a guest whose registered database exists
- **THEN** it writes `<stem>-<UTC stamp>.db` via `sqlite3 .backup` plus its `.meta` into the pre-deploy dir and prints the snapshot path
- **proof:** unit

#### Scenario: Service playbooks run the snapshot role before the service role
- **WHEN** `02_SERVICES/life-manager.yml` and `02_SERVICES/rues-arcade.yml` are read
- **THEN** each lists `sqlite_snapshot` before its service role (`life_manager` resp. `rues_arcade`)
- **proof:** unit

#### Scenario: First deploy without a database
- **WHEN** `sqlite-snapshot pre-deploy` runs and the registered database file does not exist yet
- **THEN** it prints `skip: <db> does not exist yet`, writes nothing and exits 0, so the deploy continues
- **proof:** unit

#### Scenario: Failed snapshot fails the run
- **WHEN** `sqlite3 .backup` fails during `sqlite-snapshot pre-deploy`
- **THEN** the script exits non-zero and leaves no file under a snapshot name, so the play stops before the service role changes the release
- **proof:** unit

#### Scenario: Guest keeps the newest 10 pre-deploy snapshots
- **WHEN** a pre-deploy snapshot is written while 10 already exist for that database
- **THEN** the oldest is deleted and the newest 10 remain
- **proof:** unit

#### Scenario: Re-run without a version change still snapshots
- **WHEN** a service playbook runs with the version that is already deployed
- **THEN** a new pre-deploy snapshot is written all the same
- **proof:** manual (needs a real guest; observed in the post-merge CI deploy of unit 6, which runs both playbooks without a version change)

### Requirement: Every snapshot carries metadata

Every snapshot (daily, pre-deploy and pre-restore) SHALL have a `.meta` file next to it recording the UTC timestamp, host, service, database path, kind, app release version, `PRAGMA user_version`, and the newest `schema_migrations.name` when that table exists, all read from the snapshot itself. A missing table SHALL only omit the migration name; an unknown release SHALL be recorded as `unknown` and SHALL NOT fail the snapshot.

#### Scenario: Metadata of a migrated database
- **WHEN** a snapshot is taken of a database with `user_version` 4 and a `schema_migrations` table whose newest name is `0003_wavelength.sql`, and `<release_link>/.deployed_version` reads `v0.6.0`
- **THEN** the `.meta` has `timestamp`, `host`, `service`, `database`, `kind`, `release=v0.6.0`, `user_version=4` and `schema_migration=0003_wavelength.sql`
- **proof:** unit

#### Scenario: Database without schema_migrations
- **WHEN** a snapshot is taken of a database that has no `schema_migrations` table
- **THEN** the `.meta` records `user_version` and has no `schema_migration` line
- **proof:** unit

#### Scenario: Release version unknown
- **WHEN** a snapshot is taken and the registry's release link (or its `.deployed_version`) does not exist
- **THEN** the `.meta` records `release=unknown` and the snapshot succeeds
- **proof:** unit

#### Scenario: Metadata travels with the snapshot to the node
- **WHEN** the nightly run pulls a snapshot from a guest
- **THEN** its `.meta` lands next to it under `/var/backups/homelab/<host>/<kind>/` with the same base name
- **proof:** unit

### Requirement: A nightly node job collects every registered guest

A node-side role `sqlite_backup` on proxmox1 SHALL install a script and a daily systemd timer that, for each registered guest, takes a snapshot inside the guest via `pct exec`, pulls it with `pct pull` to `/var/backups/homelab/<host>/daily/`, and copies every pre-deploy snapshot the node does not have yet to `/var/backups/homelab/<host>/pre-deploy/`. A failure on one guest (guest stopped, `pct exec` failing, database missing, service restarted mid-run, node disk full) SHALL mark that service failed and SHALL NOT stop the other guests from being processed. The job SHALL log `<host>: ok` or `<host>: FAILED (<reason>)` per guest to stderr, SHALL exit 0 only when every guest succeeded, and SHALL make no network request (no alerting; a failed run is seen in the journal and in `systemctl --failed`). A pre-deploy snapshot that fails the integrity check on the node SHALL NOT fail its guest: it is handled once as described under "Only intact snapshots are kept", and the daily snapshot alone decides the guest's status.

#### Scenario: Nightly run collects every registered guest
- **WHEN** `homelab-sqlite-backup run` runs with two registered guests that both answer
- **THEN** each guest's daily snapshot and `.meta` are under `/var/backups/homelab/<host>/daily/`, stderr has `<host>: ok` for both, and the run exits 0
- **proof:** unit

#### Scenario: New pre-deploy snapshots are copied once
- **WHEN** a guest lists three pre-deploy snapshots and the node already holds one of them
- **THEN** only the two missing ones are pulled into `/var/backups/homelab/<host>/pre-deploy/`
- **proof:** unit

#### Scenario: One guest fails, the others still run
- **WHEN** `pct exec` fails for the first registered guest (stopped guest, or the service restarted mid-snapshot)
- **THEN** the second guest is still collected and logged `<host>: ok`, the first is logged `<host>: FAILED (<reason>)` on stderr, and the run exits non-zero
- **proof:** unit

#### Scenario: Registered database missing in the guest
- **WHEN** `sqlite-snapshot daily` runs and a registered database file does not exist
- **THEN** it exits non-zero, and the node marks that service failed
- **proof:** unit

#### Scenario: Node disk full
- **WHEN** writing a pulled snapshot under `/var/backups/homelab/` fails
- **THEN** that service is marked failed, no partial file keeps a snapshot name, and the other guests are still processed
- **proof:** unit

#### Scenario: The job reports only through its log and exit status
- **WHEN** `homelab-sqlite-backup run` finishes once with every guest ok and once with one guest failed
- **THEN** neither run makes a network request (`curl` is never called), the exit status is 0 resp. non-zero, and none of the node script, its config template, the role defaults or the preflight mentions `PING_URL` or `sqlite_backup_ping_url`
- **proof:** unit

#### Scenario: Timer runs the job daily on proxmox1
- **WHEN** the node playbook has been applied to proxmox1
- **THEN** `systemctl list-timers` shows `homelab-sqlite-backup.timer` enabled with a daily next run, and a manual start of the service lands snapshots for both registered guests
- **proof:** manual (needs proxmox1 and real `pct exec`/`pct pull`; post-merge, unit 6)

### Requirement: Only intact snapshots are kept

Each pulled daily snapshot SHALL pass `PRAGMA integrity_check` on the node before it is kept; a daily snapshot that does not report `ok` SHALL be deleted together with its `.meta`, and the service SHALL be marked failed. A pre-restore snapshot (the live database about to be replaced) or a pre-deploy snapshot that does not report `ok` SHALL instead be kept under a name marked `-corrupt` (`<stem>-<UTC stamp>-corrupt.db` with its `.meta`), with a warning on stderr, and SHALL NOT fail the service or block a restore. A pre-deploy snapshot already held on the node, under its own or its `-corrupt` name, SHALL NOT be pulled again, so a corrupt one is handled once. Corrupt-marked files SHALL NOT be offered as restore sources and SHALL NOT be counted or deleted by rotation.

#### Scenario: Intact snapshot is kept
- **WHEN** a pulled snapshot's `PRAGMA integrity_check` prints `ok`
- **THEN** the snapshot and its `.meta` are kept under their final names
- **proof:** unit

#### Scenario: Corrupt snapshot is discarded
- **WHEN** a pulled daily snapshot's `PRAGMA integrity_check` prints anything other than `ok`
- **THEN** the snapshot and its `.meta` are deleted and the service is reported `FAILED`
- **proof:** unit

#### Scenario: Corrupt live database is kept marked at pre-restore
- **WHEN** `homelab-sqlite-backup pre-restore <host> <ctid>` pulls a snapshot of the live database whose `PRAGMA integrity_check` prints anything other than `ok`
- **THEN** `<stem>-<stamp>-corrupt.db` and `<stem>-<stamp>-corrupt.meta` are kept under `pre-restore/`, stderr has a warning naming the file, the name is not printed on stdout, and the command exits 0
- **proof:** unit

#### Scenario: Corrupt pre-deploy snapshot is kept marked once
- **WHEN** a guest lists a pre-deploy snapshot that fails the integrity check on the node, on two consecutive nightly runs
- **THEN** the first run keeps it as `<stem>-<stamp>-corrupt.db` with its `.meta` under `pre-deploy/` with a warning, logs `<host>: ok` and exits 0 when the daily snapshot is fine; the second run does not pull it again and prints no warning
- **proof:** unit

#### Scenario: Rotation ignores corrupt-marked snapshots
- **WHEN** a successful run rotates a directory that holds corrupt-marked files next to a full set of intact snapshots
- **THEN** the corrupt-marked files are not counted toward the keep limit and are not deleted, and the intact snapshots rotate as before
- **proof:** unit

### Requirement: Old snapshots are rotated only after a successful run

After a service's run succeeded, the node SHALL keep the newest 14 daily, the newest 10 pre-deploy and the newest 10 pre-restore snapshots per database and delete older ones (each with its `.meta`). A service whose run failed SHALL have none of its snapshots deleted.

#### Scenario: Daily rotation keeps the newest 14
- **WHEN** a successful run adds a daily snapshot while 14 already exist for that database
- **THEN** the oldest daily snapshot and its `.meta` are deleted and 14 remain
- **proof:** unit

#### Scenario: Pre-deploy rotation keeps the newest 10
- **WHEN** a successful run leaves 12 pre-deploy snapshots for a database on the node
- **THEN** the two oldest are deleted with their `.meta` and 10 remain
- **proof:** unit

#### Scenario: Pre-restore rotation keeps the newest 10
- **WHEN** `homelab-sqlite-backup pre-restore <host> <ctid>` succeeds while 10 pre-restore snapshots already exist for that database
- **THEN** the oldest pre-restore snapshot and its `.meta` are deleted and 10 remain, the new one among them
- **proof:** unit

#### Scenario: Fewer than 14 present
- **WHEN** a successful run leaves 5 daily snapshots for a database
- **THEN** nothing is deleted
- **proof:** unit

#### Scenario: Failed run deletes nothing
- **WHEN** a service's run fails while it has 20 daily snapshots on the node
- **THEN** all 20 are still there afterwards
- **proof:** unit

### Requirement: A snapshot can be restored from the workstation

A restore playbook in `ansible/playbooks/00_OPERATIONAL/` SHALL take a service host and a snapshot name, print the snapshot's metadata, save the current database as a `pre-restore` snapshot on the node, stop the unit, push the snapshot into the guest, remove stale `-wal`/`-shm` files, set owner and mode, start the unit and wait for `/healthz` to answer 200. A snapshot name that is not found (including a typo in the database stem) SHALL fail the run listing the available snapshots; a failure after the unit was stopped SHALL start the unit again before the run fails; a `/healthz` that does not answer 200 SHALL fail the run naming the pre-restore snapshot to roll back with. A registered database that no longer exists in the guest (an accidental delete) SHALL NOT block the restore: it is skipped with a message when saving the pre-restore snapshot, and the restore proceeds. A live database that fails the integrity check SHALL NOT block the restore either: its pre-restore snapshot is kept marked `-corrupt` with a warning (see "Only intact snapshots are kept"), and the restore proceeds. Any other failure while saving the pre-restore snapshot (snapshot command, pull, disk) SHALL abort the run before the unit is stopped. A snapshot name that is not found, however it was written (without `.db`, with a path), SHALL fail with the listing of available snapshots; `<kind>/<name>.db` as printed by that listing SHALL be accepted as the name to look up. A snapshot whose schema is newer than the running release is not detected automatically; the metadata is shown first and `/healthz` is the guard.

#### Scenario: Snapshot metadata is shown first
- **WHEN** `homelab-sqlite-backup locate <host> <name>` is called for an existing snapshot
- **THEN** it prints the snapshot's absolute path followed by its `.meta` and exits 0, and the restore playbook calls it before stopping anything
- **proof:** unit

#### Scenario: Snapshot name not found
- **WHEN** `homelab-sqlite-backup locate <host> <name>` is called for a name that exists in none of `daily/`, `pre-deploy/`, `pre-restore/`
- **THEN** it prints `not found: <name>` and every available `<kind>/<name>` for that host, and exits non-zero, so the playbook fails before changing anything; the playbook runs it before checking the stem against the registry, so a mistyped stem gets this listing too
- **proof:** unit

#### Scenario: Snapshot name not found in any form
- **WHEN** `homelab-sqlite-backup locate <host> <name>` is called with a name without `.db`, with a `/` that is not a known `<kind>/` prefix, or with a `<kind>/<name>.db` that does not exist
- **THEN** each prints `not found: <name>` and the available `<kind>/<name>` list, including corrupt-marked files under their `-corrupt` name, and exits 1
- **proof:** unit

#### Scenario: Snapshot given as kind and name
- **WHEN** `homelab-sqlite-backup locate <host> daily/<name>.db` is called for an existing daily snapshot
- **THEN** it prints the absolute path and the `.meta` and exits 0, and `pre-deploy/<name>.db` for a snapshot that only exists under `daily/` is not found
- **proof:** unit

#### Scenario: Current database is saved before the restore
- **WHEN** `homelab-sqlite-backup pre-restore <host> <ctid>` runs
- **THEN** a snapshot of the live database, with `.meta`, lands in `/var/backups/homelab/<host>/pre-restore/` after passing the integrity check, and its name is printed
- **proof:** unit

#### Scenario: Restore when the live database is missing
- **WHEN** `sqlite-snapshot pre-restore` runs in a guest where a registered database file does not exist
- **THEN** it prints `skip: <db> does not exist` to stderr, snapshots the other registered databases and exits 0 (a genuine snapshot failure still exits non-zero)
- **proof:** unit

#### Scenario: Failed pre-restore snapshot aborts
- **WHEN** `sqlite-snapshot pre-restore` runs and `sqlite3 .backup` fails for a registered database that exists
- **THEN** it exits non-zero with `error: snapshot of <db> failed` and leaves no file under a snapshot name, and the node's `pre-restore` command exits non-zero, so the restore playbook fails before it stops the unit
- **proof:** unit

#### Scenario: Restore proceeds when the live database is corrupt
- **WHEN** the restore playbook runs and `homelab-sqlite-backup pre-restore` exits 0 with a corrupt-database warning on stderr and no snapshot name of the chosen database on stdout
- **THEN** the playbook shows the warning, still stops the unit and pushes the snapshot, and a failed health check says there is no pre-restore snapshot to roll back to
- **proof:** unit

#### Scenario: Restore refuses a corrupt-marked snapshot
- **WHEN** the restore playbook is given a `<stem>-<stamp>-corrupt.db` name
- **THEN** it fails before saving the pre-restore snapshot or stopping the unit
- **proof:** unit

#### Scenario: Restore proceeds when the live database is gone
- **WHEN** the restore playbook runs and `homelab-sqlite-backup pre-restore` exits 0 without naming a snapshot of the chosen database
- **THEN** the playbook still stops the unit and pushes the snapshot, and a failed health check names that there is no pre-restore snapshot to roll back to
- **proof:** unit

#### Scenario: pre-restore without a container ID fails
- **WHEN** `homelab-sqlite-backup pre-restore <host>` is called without a container ID
- **THEN** it exits non-zero and pulls nothing
- **proof:** unit

#### Scenario: Restore playbook refuses --check
- **WHEN** the restore playbook runs with `--check`
- **THEN** it fails before the snapshot lookup with a message that the restore has no dry run
- **proof:** unit

#### Scenario: Restore of the oldest pre-restore snapshot
- **WHEN** the restore playbook restores the oldest of 10 pre-restore snapshots
- **THEN** its own `pre-restore` call does not rotate that snapshot away before it is pushed
- **proof:** unit

#### Scenario: Restore accepts the name as printed by the listing
- **WHEN** the restore playbook is given `<kind>/<name>.db` (`daily`, `pre-deploy` or `pre-restore`) as printed by the not-found listing
- **THEN** it looks the snapshot up under that kind, checks the stem of `<name>.db` against the registry, and passes the bare `<name>.db` to `pre-restore`, so restoring the oldest `pre-restore/` snapshot still keeps it; any other prefix, or more than one `/`, fails before the lookup
- **proof:** unit

#### Scenario: Failed restore brings the unit back
- **WHEN** a step after "Stop the service" fails
- **THEN** the playbook starts the unit again, and its failure message names the pre-restore snapshot of the restored database (not another registered database's)
- **proof:** unit

#### Scenario: Restore ends with a healthy service
- **WHEN** the restore playbook runs for `rues-arcade01` with a snapshot from the node
- **THEN** the unit runs again on the restored database, no `-wal`/`-shm` from before remains, owner and mode match the registry, `/healthz` answers 200 and the snapshot's content is visible in the app
- **proof:** manual (needs proxmox1 and a real guest; post-merge restore drill, unit 6)

#### Scenario: Restore leaves an unhealthy service
- **WHEN** `/healthz` does not answer 200 within the retries after a restore
- **THEN** the playbook fails and its message names the pre-restore snapshot and the command that restores it
- **proof:** manual (needs a deliberately broken restore on a real guest; not drilled)

### Requirement: The node role is applied by hand from the workstation

A playbook in `ansible/playbooks/00_OPERATIONAL/` SHALL apply the node-side role to the `proxmox_node` group. It SHALL be run by hand from the workstation with the node key; the deploy workflow SHALL NOT run it.

#### Scenario: The deploy never runs the node playbook
- **WHEN** the node playbook is read
- **THEN** it lives under `00_OPERATIONAL/`, which `deploy-targets.sh` never selects, and targets only `proxmox_node`
- **proof:** unit

#### Scenario: Check-mode run on proxmox1
- **WHEN** the node playbook runs with `--check` against proxmox1
- **THEN** nothing on the node changes and the output shows what would be installed; a timer unit that is not installed yet does not fail the run
- **proof:** unit (local fixture run with the apt task stubbed out) and manual (the real node run needs proxmox1; Gate 2 evidence, unit 5)

#### Scenario: Check-mode run of the service playbooks
- **WHEN** `02_SERVICES/life-manager.yml` and `02_SERVICES/rues-arcade.yml` run with `--check` from the workstation on this branch
- **THEN** nothing on the guests changes and the output shows `sqlite3`, the script and its config as would-change, with the play otherwise succeeding
- **proof:** manual (needs the real guests; Gate 2 evidence, unit 5)

### Requirement: Backups are documented and new services must register

Each new role SHALL have a README. `docs/backups.md` SHALL describe what is backed up, where, the retention, the restore steps, how to onboard a new service, and what is NOT covered (disk failure of proxmox1, non-app data). `.claude/CLAUDE.md`'s service-delivery section SHALL state that a service with persistent data must be registered in the backup registry.

#### Scenario: Onboarding a new service from the docs
- **WHEN** a reader follows the onboarding section of `docs/backups.md`
- **THEN** it takes them through setting `sqlite_backups` on the host, adding `sqlite_snapshot` before the service role, and re-running the node playbook by hand, in a few steps
- **proof:** manual (documentation; read at Gate 2)

#### Scenario: CLAUDE.md requires registration
- **WHEN** the service-delivery section of `.claude/CLAUDE.md` is read
- **THEN** it says a service with persistent data must be registered in the backup registry and points to `docs/backups.md`
- **proof:** manual (documentation; read at Gate 2)

### Requirement: The backup scripts are proven offline by proof

`scripts/proof.sh` SHALL run fixture tests for the guest and node backup scripts whenever a file they cover changes, and in `--all` mode. The tests SHALL stub `pct` and `sqlite3` and SHALL NOT contact proxmox1, a guest or any external service.

#### Scenario: Script change runs its fixture tests
- **WHEN** `scripts/proof.sh --all` runs
- **THEN** its output contains `PASS: sqlite-snapshot fixtures` and `PASS: sqlite-backup fixtures`, or the matching `INVARIANT_VIOLATION` code with the failing scenarios
- **proof:** unit
