sqlite_snapshot
===============

Guest-side half of the SQLite backups (see `docs/backups.md`). It installs the
`sqlite3` CLI and the `sqlite-snapshot` script, and on every run of a service
playbook writes a consistent snapshot of each registered database **before the
service role runs**. The node-side role `sqlite_backup` later collects these
snapshots and calls the same script for the nightly `daily` snapshot.

A host without a `sqlite_backups` variable is ignored: every task is skipped.

Requirements
------------

- Debian (bookworm/trixie) LXC; only the packaged `sqlite3` is needed.
- A `sqlite_backups` registry entry in the host's `host_vars` (shape below).
  List the role directly before the service role in the playbook.

Registry entry
--------------

    sqlite_backups:
      service: life-manager
      unit: life-manager.service
      owner: life-manager
      group: life-manager
      mode: "0640"                              # optional, default "0640"
      release_link: /opt/life-manager/current   # optional; <link>/.deployed_version -> metadata
      healthz_url: http://127.0.0.1/healthz     # optional, used by the restore playbook
      databases:
        - /var/lib/life-manager/life-manager.db

Paths are literal, not `{{ life_manager_db_path }}`: the node play reads them
without the service role loaded. Database basenames are unique per host.

Role Variables
--------------

| Variable | Default | Description |
|---|---|---|
| `sqlite_snapshot_script` | `/usr/local/sbin/sqlite-snapshot` | Where the script is installed. |
| `sqlite_snapshot_conf` | `/etc/sqlite-snapshot.conf` | Rendered from the registry entry. |
| `sqlite_snapshot_dir` | `/var/backups/sqlite-snapshot` | Snapshot root on the guest (root, `0750`). |
| `sqlite_snapshot_keep_pre_deploy` | `10` | Newest pre-deploy snapshots kept per database. |

What the snapshot does
----------------------

`sqlite-snapshot <daily|pre-deploy|pre-restore>` takes, per registered
database, `sqlite3 <db> ".backup '<tmp>'"` (busy timeout set, WAL-safe), reads
the metadata from the snapshot itself, and renames the file into place only
when complete. It prints each written `.db` path on stdout; messages go to
stderr.

- `pre-deploy` (from `tasks/snapshot.yml`): a database that does not exist yet
  is skipped with `skip: <db> does not exist yet` (first deploy). Keeps the
  newest `sqlite_snapshot_keep_pre_deploy` per database. The task is changed
  when it printed a path.
- `daily`, `pre-restore` (called by the node via `pct exec`): a missing
  database is an error. Keeps only the newest snapshot of that kind; history
  lives on the node.
- Any `.backup` failure exits non-zero and leaves no file under a snapshot
  name. In a play that fails the deploy before the release changes.
- `sqlite-snapshot list pre-deploy` prints the basenames of the existing
  pre-deploy snapshots.

On-guest layout
---------------

    /usr/local/sbin/sqlite-snapshot                          script
    /etc/sqlite-snapshot.conf                                SERVICE, RELEASE_LINK, SNAPSHOT_DIR, KEEP_PRE_DEPLOY, DATABASE (one per DB)
    /var/backups/sqlite-snapshot/<kind>/<stem>-<stamp>.db    snapshot, stamp = UTC YYYYmmddTHHMMSSZ
    /var/backups/sqlite-snapshot/<kind>/<stem>-<stamp>.meta  its metadata

The config is read as `key=value`, never sourced. Names sort chronologically,
which is what rotation relies on.

`.meta` format
--------------

    timestamp=2026-10-11T03:30:12Z
    host=life-manager01
    service=life-manager
    database=/var/lib/life-manager/life-manager.db
    kind=daily
    release=v0.2.2
    user_version=4
    schema_migration=0003_wavelength.sql

`release` comes from `<release_link>/.deployed_version` and is `unknown` when
that is missing. `schema_migration` is the newest `schema_migrations.name` and
is omitted when the table does not exist.

License
-------

MIT
