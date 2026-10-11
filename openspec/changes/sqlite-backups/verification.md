verified-at: 2ee056f

## Layer 1 (scripts/proof.sh --all, green)

Run at 2ee056f with the ignored `.terraform` cache cleared (25 sensors). With the cache present the run prints 24: `terraform init` is a conditional sensor that only runs when `terraform/environments/homelab/.terraform` is missing. Both runs green, no sensor lost.

```
PASS: Regression: arcade shares IP with check container
PASS: unique-hosts fixtures
PASS: sqlite-snapshot fixtures
PASS: sqlite-backup fixtures
PASS: check runner role has no deploy credentials
PASS: retired key path
proof: 25 sensor(s), 0 failed
```

## Layer 2 coverage

Scope as of 2026-10-11 (S6 alerting removed). Evidence: `ok: Scenario: <title>` lines from `scripts/tests/sqlite-snapshot.sh` (13 ok) and `scripts/tests/sqlite-backup.sh` (28 ok), each run directly at 2ee056f, rc 0, no non-ok lines. All 47 scenarios in the delta spec accounted for (39 distinct ok titles, 1 via proof.sh sensor, 7 manual).

Round 3: e547c8a, 1e736ce, 2ee056f are test-only (scripts/tests/sqlite-backup.sh): "Restore proceeds when the live database is gone" now reaches the health check and pins the push; node-side "Restore when the live database is missing" asserts node-script behaviour instead of stub text; "Check-mode run on proxmox1" pins `changed:` on the five would-install tasks. No role, playbook or script code changed since 5f92228, so the live evidence below stays valid.

Round 2: fd240d6 pins the preflight `fail_msg` wording in "Registered host without a container ID" and "Registered database path without .db suffix" (asserts now match the full message); 5f92228 adds the two scenarios "Restore when the live database is missing" and "Restore proceeds when the live database is gone".

| Scenario | proof | Evidence |
|---|---|---|
| Life-Manager and Rues-Arcade are registered | unit | `scripts/tests/sqlite-snapshot.sh` ok ✓ |
| Guest role skips a host without a registry entry | unit | `scripts/tests/sqlite-snapshot.sh` ok ✓ |
| Node playbook ignores a host without a registry entry | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Registered host without a container ID | unit | `scripts/tests/sqlite-backup.sh` ok ✓ (asserts full fail_msg "guest_c has sqlite_backups but no lxc_ctid") |
| Registered database path without .db suffix | unit | `scripts/tests/sqlite-backup.sh` ok ✓ (asserts full fail_msg "guest_d registers a database path that does not end in .db") |
| Role rejects a database path without .db suffix | unit | `scripts/tests/sqlite-snapshot.sh` ok ✓ |
| Pre-deploy snapshot is written | unit | `scripts/tests/sqlite-snapshot.sh` ok ✓ |
| Service playbooks run the snapshot role before the service role | unit | `scripts/tests/sqlite-snapshot.sh` ok ✓ |
| First deploy without a database | unit | `scripts/tests/sqlite-snapshot.sh` ok ✓ |
| Failed snapshot fails the run | unit | `scripts/tests/sqlite-snapshot.sh` ok ✓ |
| Guest keeps the newest 10 pre-deploy snapshots | unit | `scripts/tests/sqlite-snapshot.sh` ok ✓ |
| Re-run without a version change still snapshots | manual | post-merge 6.2 |
| Metadata of a migrated database | unit | `scripts/tests/sqlite-snapshot.sh` ok ✓ |
| Database without schema_migrations | unit | `scripts/tests/sqlite-snapshot.sh` ok ✓ |
| Release version unknown | unit | `scripts/tests/sqlite-snapshot.sh` ok ✓ |
| Metadata travels with the snapshot to the node | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Nightly run collects every registered guest | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| New pre-deploy snapshots are copied once | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| One guest fails, the others still run | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Registered database missing in the guest | unit | `scripts/tests/sqlite-snapshot.sh` ok + `scripts/tests/sqlite-backup.sh` ok ✓ |
| Node disk full | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| The job reports only through its log and exit status | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Timer runs the job daily on proxmox1 | manual | post-merge 6.3 |
| Intact snapshot is kept | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Corrupt snapshot is discarded | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Daily rotation keeps the newest 14 | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Pre-deploy rotation keeps the newest 10 | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Pre-restore rotation keeps the newest 10 | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Fewer than 14 present | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Failed run deletes nothing | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Snapshot metadata is shown first | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Snapshot name not found | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Current database is saved before the restore | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Restore when the live database is missing | unit | `scripts/tests/sqlite-snapshot.sh` ok + `scripts/tests/sqlite-backup.sh` ok ✓ |
| Restore proceeds when the live database is gone | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| pre-restore without a container ID fails | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Restore playbook refuses --check | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Restore of the oldest pre-restore snapshot | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Failed restore brings the unit back | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Restore ends with a healthy service | manual | post-merge 6.4 restore drill |
| Restore leaves an unhealthy service | manual | not drilled (needs deliberately broken restore) |
| The deploy never runs the node playbook | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Check-mode run on proxmox1 | unit + manual | B ok (fixture, pins `changed:` on the five would-install tasks); live (round 1 evidence, still valid: fd240d6/5f92228 and the round-3 test-only commits did not touch the node role's tasks/templates or the sqlite_snapshot role's tasks/config; only the scripts, restore playbook, docs and tests changed): check log `sqlite_backup_check.log` (exit 0): preflight asserts ok for life-manager01 and rues-arcade01, "Show the guests the nightly job will cover" lists `life-manager01 223`, `rues-arcade01 100`; would-change: backup root, script, config, service unit, timer unit (`changed`, 5); `sqlite3` already installed (ok); recap `proxmox1 ok=14 changed=5 unreachable=0 failed=0` |
| Check-mode run of the service playbooks | manual | 5.3 evidence from a02644d, run at 3c993f1 (sqlite_snapshot role tasks/config and 02_SERVICES playbooks unchanged since, also through 5f92228; only the snapshot script gained a pre-restore skip branch): both playbooks exit 0, `ok=36 changed=4 failed=0`; would-change = apt sqlite3, snapshot script, config, snapshot dir; snapshot task skipped in check mode |
| Onboarding a new service from the docs | manual | Gate 2 read of docs/backups.md |
| CLAUDE.md requires registration | manual | Gate 2 read of .claude/CLAUDE.md |
| Script change runs its fixture tests | unit | `scripts/proof.sh --all` prints `PASS: sqlite-snapshot fixtures` and `PASS: sqlite-backup fixtures` |

Gaps: none

Notes:
- "Check-mode run on proxmox1": the live run shows `sqlite3` as already installed on the node (ok, not would-change); the other planned installs show as changed. Check mode skips command tasks, so only the planned file/unit changes are proven live.
- The sqlite-backup fixtures need `~/.config/homelab/vault_pass` (ansible.cfg `vault_password_file`); CI writes a dummy file.

## Manual checklist

- Read docs/backups.md onboarding section (Scenario: Onboarding a new service from the docs)
- Read the service-delivery section of .claude/CLAUDE.md for the registration rule (Scenario: CLAUDE.md requires registration)
- Post-merge 6.1: run `sqlite_backup.yml` for real on proxmox1
- Post-merge 6.2: CI deploy of both services; each guest has a pre-deploy snapshot although no version changed (Scenario: Re-run without a version change still snapshots)
- Post-merge 6.3: `systemctl start homelab-sqlite-backup.service`; timer listed, both guests have daily `.db` + `.meta`, journal shows `<host>: ok` (Scenario: Timer runs the job daily on proxmox1)
- Post-merge 6.4: restore drill on rues-arcade01 (Scenario: Restore ends with a healthy service)
- Not drilled: Scenario: Restore leaves an unhealthy service

## Diffstat

origin/main...flow/sqlite-backups: 41 files changed, 2909 insertions(+), 1 deletion(-)

## Screenshots

none
