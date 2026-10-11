verified-at: 5775ac8

## Layer 1 (scripts/proof.sh --all, green)

Run at 5775ac8 with the ignored `.terraform` cache cleared (25 sensors), rc 0.

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

Scope as of 2026-10-11 (S6 alerting removed). Evidence: `ok: Scenario: <title>` lines from `scripts/tests/sqlite-snapshot.sh` (16 ok lines) and `scripts/tests/sqlite-backup.sh` (38 ok lines), each run directly at 5775ac8, rc 0, no non-ok lines. All 55 scenarios in the delta spec accounted for: 46 unit via a named ok line, 1 unit+manual (Check-mode run on proxmox1) with a named ok line, 1 via the proof.sh sensors, 7 manual (one of them, "Check-mode run on proxmox1", is unit + manual).

Round 4 (506c1ce, ea7d84c, f06e24c, 5775ac8): 8 scenarios added (corrupt-marked snapshots, locate on every not-found path and `kind/name`, failed pre-restore snapshot, corrupt live DB at restore, refusing corrupt-marked names); 3 existing requirement texts widened ("Only intact snapshots are kept" now daily-only, node job requirement, restore playbook requirement). Changed since 2ee056f: restore playbook, node script, sqlite_backup README, docs, design/spec, the two test scripts. Both round-3 open findings (pre-restore failure test, locate listing) now have named passing tests.

Earlier rounds: round 3 e547c8a/1e736ce/2ee056f test-only; round 2 fd240d6 (full fail_msg asserts) and 5f92228 (live DB missing scenarios).

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
| Corrupt live database is kept marked at pre-restore | unit | `scripts/tests/sqlite-backup.sh` ok ✓ (added round 4) |
| Corrupt pre-deploy snapshot is kept marked once | unit | `scripts/tests/sqlite-backup.sh` ok ✓ (added round 4) |
| Rotation ignores corrupt-marked snapshots | unit | `scripts/tests/sqlite-backup.sh` ok ✓ (added round 4) |
| Daily rotation keeps the newest 14 | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Pre-deploy rotation keeps the newest 10 | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Pre-restore rotation keeps the newest 10 | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Fewer than 14 present | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Failed run deletes nothing | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Snapshot metadata is shown first | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Snapshot name not found | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Snapshot name not found in any form | unit | `scripts/tests/sqlite-backup.sh` ok ✓ (added round 4) |
| Snapshot given as kind and name | unit | `scripts/tests/sqlite-backup.sh` ok ✓ (added round 4) |
| Current database is saved before the restore | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Restore when the live database is missing | unit | `scripts/tests/sqlite-snapshot.sh` ok + `scripts/tests/sqlite-backup.sh` ok ✓ |
| Failed pre-restore snapshot aborts | unit | `scripts/tests/sqlite-snapshot.sh` ok + `scripts/tests/sqlite-backup.sh` ok ✓ (added round 4; closes round-3 weak-test finding) |
| Restore proceeds when the live database is corrupt | unit | `scripts/tests/sqlite-backup.sh` ok ✓ (added round 4) |
| Restore refuses a corrupt-marked snapshot | unit | `scripts/tests/sqlite-backup.sh` ok ✓ (added round 4) |
| Restore proceeds when the live database is gone | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| pre-restore without a container ID fails | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Restore playbook refuses --check | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Restore of the oldest pre-restore snapshot | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Failed restore brings the unit back | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Restore ends with a healthy service | manual | post-merge 6.4 restore drill |
| Restore leaves an unhealthy service | manual | not drilled (needs deliberately broken restore) |
| The deploy never runs the node playbook | unit | `scripts/tests/sqlite-backup.sh` ok ✓ |
| Check-mode run on proxmox1 | unit + manual | B ok (fixture, pins `changed:` on the five would-install tasks); live (round 1 evidence, still valid after round 4: since 2ee056f only the node script `homelab-sqlite-backup`, `sqlite_restore.yml`, the sqlite_backup README, docs and tests changed; no role tasks/templates/defaults, no sqlite_snapshot file and no node or service playbook): check log `sqlite_backup_check.log` (exit 0): preflight asserts ok for life-manager01 and rues-arcade01, "Show the guests the nightly job will cover" lists `life-manager01 223`, `rues-arcade01 100`; would-change: backup root, script, config, service unit, timer unit (`changed`, 5); `sqlite3` already installed (ok); recap `proxmox1 ok=14 changed=5 unreachable=0 failed=0` |
| Check-mode run of the service playbooks | manual | 5.3 evidence from a02644d, run at 3c993f1 (sqlite_snapshot role tasks/config/script and 02_SERVICES playbooks unchanged since, also through 5775ac8): both playbooks exit 0, `ok=36 changed=4 failed=0`; would-change = apt sqlite3, snapshot script, config, snapshot dir; snapshot task skipped in check mode |
| Onboarding a new service from the docs | manual | Gate 2 read of docs/backups.md |
| CLAUDE.md requires registration | manual | Gate 2 read of .claude/CLAUDE.md |
| Script change runs its fixture tests | unit | `scripts/proof.sh --all` prints `PASS: sqlite-snapshot fixtures` and `PASS: sqlite-backup fixtures` |

Gaps: none

Notes:
- "Check-mode run on proxmox1": the live run shows `sqlite3` as already installed on the node (ok, not would-change); the other planned installs show as changed. Check mode skips command tasks, so only the planned file/unit changes are proven live.
- The sqlite-backup fixtures need `~/.config/homelab/vault_pass` (ansible.cfg `vault_password_file`); CI writes a dummy file.
- The new restore-playbook task "Show the pre-restore warnings" is exercised by "Restore proceeds when the live database is corrupt" in the fixture; it was not part of any live run.

## Manual checklist

- Read docs/backups.md onboarding section (Scenario: Onboarding a new service from the docs)
- Read the service-delivery section of .claude/CLAUDE.md for the registration rule (Scenario: CLAUDE.md requires registration)
- Post-merge 6.1: run `sqlite_backup.yml` for real on proxmox1
- Post-merge 6.2: CI deploy of both services; each guest has a pre-deploy snapshot although no version changed (Scenario: Re-run without a version change still snapshots)
- Post-merge 6.3: `systemctl start homelab-sqlite-backup.service`; timer listed, both guests have daily `.db` + `.meta`, journal shows `<host>: ok` (Scenario: Timer runs the job daily on proxmox1)
- Post-merge 6.4: restore drill on rues-arcade01 (Scenario: Restore ends with a healthy service)
- Not drilled: Scenario: Restore leaves an unhealthy service

## Diffstat

origin/main...flow/sqlite-backups: 41 files changed, 3193 insertions(+), 1 deletion(-)

## Screenshots

none

## Review

Fresh-context reviewer (opus), three rounds against `origin/main...flow/sqlite-backups`.

### Round 1 (at f56e552)
- [weak] "Registered database path without .db suffix" matched loop label and assertion text, not the fail_msg → fixed in fd240d6 (asserts the full fail_msg; red under a "bad input" mutation).
- [weak] "Registered host without a container ID", same cause → fixed in fd240d6.
- [correctness] Restore failed when the live database was missing (guest `pre-restore` errored) → fixed in 5f92228: `pre-restore` skips a missing DB like `pre-deploy`; new scenarios "Restore when the live database is missing" and "Restore proceeds when the live database is gone".

### Round 2 (at 5f92228)
- [weak] "Restore proceeds when the live database is gone" never reached the health check (pct stub failed every push) → fixed in e547c8a (push succeeds in that fixture, push and healthz pinned; red when the push task is deleted).
- [weak, low] node-side "Restore when the live database is missing" asserted stub text → fixed in 1e736ce (asserts node-script behaviour: exit 0, no pull, no node dir).
- [weak, low] "Check-mode run on proxmox1" didn't pin `changed:` → fixed in 2ee056f (five would-install tasks pinned; red under `changed_when: false`).
- [note] `.meta` renamed before `.db` could orphan a `.meta` if the second same-directory rename failed → not fixed: not realistically triggerable.

### Round 3 (at 2ee056f) — round limit reached, open for Gate 2
- [weak] `scripts/tests/sqlite-snapshot.sh:190-201` — THEN "(a genuine snapshot failure still exits non-zero)" is not tested for `pre-restore`; a mutation making pre-restore always exit 0 stayed green. Open.
- [spec mismatch] `homelab-sqlite-backup:143-146` (`cmd_locate`) — a name without `.db` or with a `/` (e.g. `daily/<name>.db` as printed by locate's own listing) returns `not found` without listing the available snapshots. Open.
- [design note] A corrupt live database fails the pre-restore integrity check, so the restore playbook stops before "Stop the service" — restore is blocked exactly when the DB is broken; only a missing DB is exempt. A corrupt pre-deploy snapshot in a guest marks that host FAILED nightly until it rotates out. Open — decision for Rue.
