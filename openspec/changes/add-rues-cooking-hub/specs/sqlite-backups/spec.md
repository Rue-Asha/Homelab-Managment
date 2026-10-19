## MODIFIED Requirements

### Requirement: One registry entry per service host drives every backup step

Each service host whose service keeps a SQLite database SHALL declare one inventory variable, `sqlite_backups`, holding its database path(s), systemd unit and owner, and this variable SHALL be the single source the guest-side role, the node-side role and the restore playbook read. Life-Manager (`life-manager01`), Rues-Arcade (`rues-arcade01`) and Rues-Cooking-Hub (`rues-cooking-hub01`) SHALL be registered. A host without the variable SHALL be ignored by both roles. A host that has the variable but no `lxc_ctid` SHALL make the node playbook fail with a message naming that host.

#### Scenario: Life-Manager and Rues-Arcade are registered
- **WHEN** `host_vars/life-manager01/vars.yml` and `host_vars/rues-arcade01/vars.yml` are read
- **THEN** each defines `sqlite_backups` with unit, owner and the literal database path `/var/lib/life-manager/life-manager.db` resp. `/var/lib/rues-arcade/rues-arcade.db`
- **proof:** unit

#### Scenario: Rues-Cooking-Hub is registered
- **WHEN** `host_vars/rues-cooking-hub01/vars.yml` is read
- **THEN** it defines `sqlite_backups` with unit `rues-cooking-hub.service`, owner `rues-cooking-hub` and the literal database path `/var/lib/rues-cooking-hub/rues-cooking-hub.db`
- **proof:** manual (one-shot python check recorded in `verification.md`; Rue chose not to extend the hardcoded hosts in `scripts/tests/sqlite-snapshot.sh`)

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

#### Scenario: The Rues-Cooking-Hub playbook runs the snapshot role before its service role
- **WHEN** `02_SERVICES/rues-cooking-hub.yml` is read
- **THEN** it lists `sqlite_snapshot` before `rues_cooking_hub`
- **proof:** manual (one-shot python check recorded in `verification.md`; Rue chose not to extend the hardcoded playbooks in `scripts/tests/sqlite-snapshot.sh`)

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
