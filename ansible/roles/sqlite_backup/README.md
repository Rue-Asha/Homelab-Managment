# sqlite_backup

Installs a nightly job on the Proxmox node (`proxmox1`) that collects the SQLite
snapshots of every registered service guest with `pct exec` / `pct pull`, checks
them, and rotates them. The guest side is the
`sqlite_snapshot` role; what is backed up and how to restore is in `docs/backups.md`.

**Runs only from the workstation.** `ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml`
targets `proxmox_node` and needs the node key. CI and `deploy.yml` cannot reach
the node and never run it (`deploy-targets.sh` only selects `02_SERVICES`).

```
scripts/fetch-inventory.sh
ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml --check
ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml
```

Re-run it whenever a service is registered or removed.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `sqlite_backup_root` | `/var/backups/homelab` | Where snapshots land on the node. |
| `sqlite_backup_keep_daily` | `14` | Newest daily snapshots kept per database. |
| `sqlite_backup_keep_pre_deploy` | `10` | Newest pre-deploy snapshots kept per database. |
| `sqlite_backup_keep_pre_restore` | `10` | Newest pre-restore snapshots kept per database. |
| `sqlite_backup_snapshot_cmd` | `/usr/local/sbin/sqlite-snapshot` | Guest script the node calls; must equal the guest role's `sqlite_snapshot_script`. |
| `sqlite_backup_guest_timeout` | `300` | Seconds each `pct`/`sqlite3` call may take; a timeout fails that guest only. |
| `sqlite_backup_on_calendar` | `*-*-* 03:30:00` | Timer schedule (`OnCalendar=`). |
| `sqlite_backup_script`, `sqlite_backup_conf` | `/usr/local/sbin/homelab-sqlite-backup`, `/etc/homelab-sqlite-backup.conf` | Install paths. |

## Preflight

`tasks/preflight.yml` (tag `preflight`, always runs) fails before anything is
installed when a host that has `sqlite_backups` has
no `lxc_ctid` or a database path not ending in `.db` (the message names the host). It then prints the `<host> <ctid>`
list that goes into the config as `GUEST=` lines. Hosts without `sqlite_backups`
are ignored. Check the printed list after onboarding a service.

## Node layout

```
/var/backups/homelab/<host>/daily/        <stem>-<YYYYmmddTHHMMSSZ>.db + .meta
/var/backups/homelab/<host>/pre-deploy/
/var/backups/homelab/<host>/pre-restore/
```

Pulls go to hidden temp names in the target dir and are renamed into place only
after `PRAGMA integrity_check` prints `ok`. Rotation sorts by file name (the UTC
stamp) and runs only for a guest whose run succeeded.

A pre-deploy snapshot, or the pre-restore snapshot of a live database, that
fails the integrity check is kept as `<stem>-<stamp>-corrupt.db` + `.meta`
(warning on stderr, not a failure) instead of being deleted; the nightly run does
not pull a corrupt pre-deploy snapshot again. The `-corrupt` name does not match
the `<stem>-<stamp>.db` pattern, so rotation ignores these files (clean up by
hand) and the restore playbook refuses them. A corrupt daily snapshot is still
deleted and fails the guest.

## Script

`/usr/local/sbin/homelab-sqlite-backup`, config `/etc/homelab-sqlite-backup.conf`
(root, 0600, `key=value`, read not sourced; override path with
`HOMELAB_SQLITE_BACKUP_CONF`).

- `run`: what the timer calls. Per guest: daily snapshot in the guest, pull and check, copy missing pre-deploy snapshots, rotate. Logs `<host>: ok` or `<host>: FAILED (<reason>)` to stderr; one failed guest does not stop the others. The exit status is 0 only when every guest succeeded; the job reports nowhere else.
- `pre-restore <host> <ctid> [<snapshot.db>]`: snapshot the live database into `pre-restore/`, check, rotate (never deleting `<snapshot.db>`, the snapshot about to be restored), print the kept `.db` name per database (none for a database that no longer exists in the guest, nor for a corrupt one, which is kept as `-corrupt` with a stderr warning; the restore proceeds without a snapshot of it). Any other failure exits non-zero. Used by `sqlite_restore.yml`.
- `locate <host> <snapshot.db>`: prints the absolute path and the `.meta`, or `not found: <name>` plus the available `<kind>/<name>` (corrupt-marked ones included) on stderr (exit 1), whatever the input looked like. `<kind>/<name>.db` is accepted. Used by `sqlite_restore.yml`.

## Timer

`homelab-sqlite-backup.timer` (`Persistent=true`) starts the oneshot
`homelab-sqlite-backup.service`. To run it once by hand on the node:
`systemctl start homelab-sqlite-backup.service`.

## Tests

`scripts/tests/sqlite-backup.sh` (run by `scripts/proof.sh`) tests the script with
stub `pct`, `sqlite3` and a `curl` tripwire (it only records calls; the job must make none), and the preflight with `--check` against a
fixture inventory of `ansible_connection: local` hosts. Real `pct` behaviour is
only proven by the post-merge run on the node.
