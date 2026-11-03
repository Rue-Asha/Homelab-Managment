## MODIFIED Requirements

### Requirement: One registry entry per service host drives every backup step

Each service host whose service keeps a SQLite database SHALL declare one inventory variable, `sqlite_backups`, holding its database path(s), systemd unit and owner, and this variable SHALL be the single source the guest-side role, the node-side role and the restore playbook read. Life-Manager (`life-manager01`), Rues-Arcade (`rues-arcade01`), Rues-Cooking-Hub (`rues-cooking-hub01`), Creative-Archive (`creative-archive01`) and Notes-Archive (`notes-archive01`) SHALL be registered, and `scripts/tests/sqlite-snapshot.sh` SHALL check each of their registry entries. A host without the variable SHALL be ignored by both roles. A host that has the variable but no `lxc_ctid` SHALL make the node playbook fail with a message naming that host.

#### Scenario: Life-Manager and Rues-Arcade are registered
- **WHEN** `host_vars/life-manager01/vars.yml` and `host_vars/rues-arcade01/vars.yml` are read
- **THEN** each defines `sqlite_backups` with unit, owner and the literal database path `/var/lib/life-manager/life-manager.db` resp. `/var/lib/rues-arcade/rues-arcade.db`
- **proof:** unit

#### Scenario: Rues-Cooking-Hub is registered
- **WHEN** `host_vars/rues-cooking-hub01/vars.yml` is read
- **THEN** it defines `sqlite_backups` with unit `rues-cooking-hub.service`, owner `rues-cooking-hub` and the literal database path `/var/lib/rues-cooking-hub/rues-cooking-hub.db`
- **proof:** unit ("Scenario: Rues-Cooking-Hub is registered" in `scripts/tests/sqlite-snapshot.sh`)

#### Scenario: Creative-Archive is registered
- **WHEN** `host_vars/creative-archive01/vars.yml` is read
- **THEN** it defines `sqlite_backups` with unit `creative-archive.service`, owner `creative-archive` and the literal database path `/var/lib/creative-archive/creative-archive.db`; while the file is missing the check fails naming that path
- **proof:** unit ("Scenario: Creative-Archive is registered" in `scripts/tests/sqlite-snapshot.sh`, red before the host_vars file exists)

#### Scenario: Notes-Archive is registered
- **WHEN** `host_vars/notes-archive01/vars.yml` is read
- **THEN** it defines `sqlite_backups` with unit `notes-archive.service`, owner `notes-archive` and the literal database path `/var/lib/notes-archive/notes-archive.db` (the database only, never its `-wal`/`-shm` files); while the file is missing the check fails naming that path
- **proof:** unit ("Scenario: Notes-Archive is registered" in `scripts/tests/sqlite-snapshot.sh`, red before the host_vars file exists)

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

The guest-side role `sqlite_snapshot` SHALL install the `sqlite3` CLI and, on every run of a service playbook, SHALL write a consistent `sqlite3 .backup` (WAL-safe) snapshot of each registered database to a pre-deploy directory on the guest before the service role runs, keeping the newest 10 per database. If a snapshot fails the play SHALL fail before the release changes. A database that does not exist yet SHALL be skipped with a message. `scripts/tests/sqlite-snapshot.sh` SHALL check the role order of the Life-Manager, Rues-Arcade, Rues-Cooking-Hub, Creative-Archive and Notes-Archive playbooks.

#### Scenario: Pre-deploy snapshot is written
- **WHEN** `sqlite-snapshot pre-deploy` runs on a guest whose registered database exists
- **THEN** it writes `<stem>-<UTC stamp>.db` via `sqlite3 .backup` plus its `.meta` into the pre-deploy dir and prints the snapshot path
- **proof:** unit

#### Scenario: Service playbooks run the snapshot role before the service role
- **WHEN** `02_SERVICES/life-manager.yml` and `02_SERVICES/rues-arcade.yml` are read
- **THEN** each lists `sqlite_snapshot` before its service role (`life_manager` resp. `rues_arcade`)
- **proof:** unit

#### Scenario: The Rues-Cooking-Hub playbook runs the snapshot role before its service role
- **WHEN** `02_SERVICES/rues-cooking-hub.yml` is read
- **THEN** it lists `sqlite_snapshot` before `rues_cooking_hub`
- **proof:** unit ("Scenario: The Rues-Cooking-Hub playbook runs the snapshot role before its service role" in `scripts/tests/sqlite-snapshot.sh`)

#### Scenario: The Creative-Archive playbook runs the snapshot role before its service role
- **WHEN** `02_SERVICES/creative-archive.yml` is read
- **THEN** it lists `sqlite_snapshot` before `creative_archive`; while the playbook is missing the check fails naming it
- **proof:** unit ("Scenario: The Creative-Archive playbook runs the snapshot role before its service role" in `scripts/tests/sqlite-snapshot.sh`, red before the playbook exists)

#### Scenario: The Notes-Archive playbook runs the snapshot role before its service role
- **WHEN** `02_SERVICES/notes-archive.yml` is read
- **THEN** it lists `sqlite_snapshot` before `notes_archive`; while the playbook is missing the check fails naming it
- **proof:** unit ("Scenario: The Notes-Archive playbook runs the snapshot role before its service role" in `scripts/tests/sqlite-snapshot.sh`, red before the playbook exists)

#### Scenario: A WAL database is copied with the online backup
- **WHEN** the Notes-Archive database runs in WAL mode with `notes-archive.db-wal` and `-shm` beside it and a snapshot is taken
- **THEN** the snapshot goes through `sqlite3 .backup` with a busy timeout, never a file copy of the `.db` alone, so committed pages still in the `-wal` file are in the snapshot; no role or registry change is needed for it
- **proof:** unit ("Scenario: Pre-deploy snapshot is written" in `scripts/tests/sqlite-snapshot.sh` asserts the `.backup` call and the busy timeout)

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

## ADDED Requirements

### Requirement: The Notes-Archive database joins the nightly backup

After the first healthy deploy and the first rollout's manual `00_OPERATIONAL/sqlite_backup.yml` run, the nightly node job on proxmox1 SHALL collect `notes-archive01`'s database like every other registered guest, and `docs/backups.md` SHALL name Notes-Archive among the backed-up apps. The runbook SHALL order `scripts/fetch-inventory.sh` (which brings `lxc_ctid`) before `sqlite_backup.yml`, and `sqlite_backup.yml` after the first healthy deploy.

#### Scenario: docs/backups.md names Notes-Archive
- **WHEN** `rg -n 'Notes-Archive' docs/backups.md` runs
- **THEN** the intro names Notes-Archive next to Life-Manager, Rues-Arcade, Rues-Cooking-Hub and Creative-Archive
- **proof:** manual (one-shot command recorded in `verification.md`; prose read at Gate 2)

#### Scenario: The rendered inventory comes before the backup registration
- **WHEN** `sqlite_backup.yml` runs from a workstation whose inventory was rendered before the apply
- **THEN** `notes-archive01` is not in the inventory and is silently not collected, so the runbook runs `scripts/fetch-inventory.sh` and checks `ansible-inventory --graph` for `notes-archive01` with an `lxc_ctid` first; a registered host that is listed without an `lxc_ctid` fails the play naming that host
- **proof:** unit ("Scenario: Registered host without a container ID" in `scripts/tests/sqlite-backup.sh` for the missing `lxc_ctid`); manual (runbook order, doc review at Gate 2)

#### Scenario: Registering before the first healthy deploy fails the nightly run
- **WHEN** `sqlite_backup.yml` registers `notes-archive01` while its database does not exist yet (no release deployed)
- **THEN** every nightly run marks `notes-archive01` failed and exits non-zero; the runbook therefore registers the backup only after `/healthz` answered 200
- **proof:** unit ("Scenario: Registered database missing in the guest" in `scripts/tests/sqlite-backup.sh`); manual (runbook order, doc review at Gate 2)

#### Scenario: The Notes-Archive database joins the nightly backup
- **WHEN** after the first healthy deploy Rue runs `scripts/fetch-inventory.sh` and `00_OPERATIONAL/sqlite_backup.yml` from the workstation
- **THEN** the next nightly run on proxmox1 logs `notes-archive01: ok` and `/var/backups/homelab/notes-archive01/daily/` holds a `notes-archive-<stamp>.db` with its `.meta`
- **proof:** manual (post-merge; needs proxmox1 and the live guest)
