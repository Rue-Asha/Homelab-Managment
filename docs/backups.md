# SQLite backups

Life-Manager and Rues-Arcade each keep their data in one SQLite file inside
their own LXC. Three kinds of snapshot protect it. Everything is driven by one
registry variable per service host, `sqlite_backups`.

## What is backed up, and where

Only the application databases of registered service hosts. Nothing else.

| Kind | Taken | Written to (guest) | Copied to (proxmox1) |
|---|---|---|---|
| `daily` | nightly by the node job | `/var/backups/sqlite-snapshot/daily/` (newest only) | `/var/backups/homelab/<host>/daily/` |
| `pre-deploy` | every run of the service's `02_SERVICES` playbook, before the service role | `/var/backups/sqlite-snapshot/pre-deploy/` | `/var/backups/homelab/<host>/pre-deploy/` (copied by the next nightly run) |
| `pre-restore` | by the restore playbook, before it overwrites the DB | `/var/backups/sqlite-snapshot/pre-restore/` (newest only) | `/var/backups/homelab/<host>/pre-restore/` |

Snapshots are named `<db stem>-<YYYYmmddTHHMMSSZ>.db` with a `.meta` next to
them. They are made with `sqlite3 .backup`, so they are consistent while the
service runs. The node checks every pulled snapshot with `PRAGMA
integrity_check` before it keeps it.

The nightly job is `homelab-sqlite-backup.timer` on proxmox1. A guest that
fails does not stop the others.

## Retention

On the node, per database: newest **14 daily**, newest **10 pre-deploy**,
newest **10 pre-restore**. A service whose run failed keeps all its old
snapshots. On the guest, pre-deploy keeps the newest 10; daily and pre-restore
keep only the newest (history lives on the node).

A Terraform recreate of a guest wipes its guest-local pre-deploy snapshots that
the node has not copied yet. The node copies them within a day.

## Metadata

`<snapshot>.meta`, `key=value` per line, read from the snapshot itself:

```
timestamp=2026-10-11T03:30:12Z
host=life-manager01
service=life-manager
database=/var/lib/life-manager/life-manager.db
kind=daily
release=v0.2.2            # unknown when the release link has no .deployed_version
user_version=4
schema_migration=0003_wavelength.sql   # only when a schema_migrations table exists
```

## Alerting

The node job pings healthchecks.io: a success ping when every service
succeeded, a fail ping listing the failed services otherwise. A job that never
runs is caught by the missing ping (grace is set on healthchecks.io). The ping
URL is `sqlite_backup_ping_url` in `ansible/inventory/host_vars/proxmox1/vault.yml`
(ansible-vault, same inline style as `host_vars/pihole01/vault.yml`).

## Applying the node role

CI cannot reach proxmox1 (`docs/deploy-runner.md`), so the node playbook runs by
hand from the workstation with the node key:

```
scripts/fetch-inventory.sh
ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml --check   # dry run
ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml
```

Re-run it whenever a service is registered or removed; its preflight lists the
hosts the nightly job will cover. To run the job once by hand, on proxmox1:
`systemctl start homelab-sqlite-backup.service`.

## Restore

From the workstation (same inventory and node key as above):

1. Pick a snapshot: `ls /var/backups/homelab/<host>/{daily,pre-deploy,pre-restore}/` on proxmox1.
2. Run:
   ```
   ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_restore.yml \
     -l <host> -e sqlite_restore_snapshot=<name>.db
   ```
3. The playbook prints the snapshot's metadata first, saves the current DB as a
   `pre-restore` snapshot on the node, stops the unit, pushes the snapshot in,
   removes `-wal`/`-shm`, sets owner and mode from the registry, starts the
   unit and waits for `/healthz` to answer 200.

An unknown snapshot name fails before anything is touched, listing what is
available. The playbook refuses `--check`: saving the pre-restore snapshot writes.

**Rolling back a restore:** if `/healthz` never answers 200, the playbook fails
and prints the pre-restore snapshot name and the exact command. It is the same
playbook with that name:

```
ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_restore.yml \
  -l <host> -e sqlite_restore_snapshot=<pre-restore name>.db
```

Check the printed metadata before restoring: if the snapshot's `user_version` or
`schema_migration` is newer than the release that is running, the restore is not
stopped automatically. `/healthz` is the only guard.

## Onboarding a new service

1. In `ansible/inventory/host_vars/<host>/vars.yml` add the registry entry with
   literal paths:
   ```yaml
   sqlite_backups:
     service: my-service
     unit: my-service.service
     owner: my-service
     group: my-service
     mode: "0640"                           # optional, default 0640
     release_link: /opt/my-service/current  # optional, for the release in .meta
     healthz_url: http://127.0.0.1/healthz  # optional, default as shown
     databases:
       - /var/lib/my-service/my-service.db  # must end in .db; stems unique per host
   ```
2. In the service's `02_SERVICES` playbook list `sqlite_snapshot` directly
   before the service role.
3. Make sure the host has an `lxc_ctid` (it does if Terraform provisions it).
4. Merge; the deploy installs the guest script and takes the first pre-deploy
   snapshot.
5. Re-run the node playbook by hand (see above) so the nightly job includes the
   host. Check the preflight output lists it.

## Not covered

- **Disk failure of proxmox1.** Backups sit on the same disk as the guests.
  A copy to the workstation or a second disk is a possible later change.
- Anything but the registered app databases: `pihole01`, `runner01` (Terraform
  state, vault password), the workstation.
- Encryption of snapshots.
- A snapshot whose schema is newer than the running release (not detected on restore).
- Automatic restore drills; the nightly integrity check and the restore
  playbook's healthz check are the only verification.
