verified-at: 2df3e08

## Layer 1 (scripts/proof.sh --all, green)

```
PASS: workflow-triggers fixtures
PASS: Regression: arcade shares IP with check container
PASS: unique-hosts fixtures
PASS: sqlite-snapshot fixtures
PASS: sqlite-backup fixtures
PASS: check runner role has no deploy credentials
PASS: retired key path
proof: 24 sensor(s), 0 failed
```

## Layer 2 coverage

Unit scenarios: ok lines from scripts/tests/sqlite-snapshot.sh (S) and scripts/tests/sqlite-backup.sh (B), each run directly 5 times at 2df3e08 (round 3), 10/10 rc 0, no non-ok lines in any run, no flake. All 34 unit scenarios map to a spec scenario; the 11 spec scenarios not in the test output are manual or covered by proof.sh PASS lines.

| Scenario | proof | Evidence |
|---|---|---|
| Life-Manager and Rues-Arcade are registered | unit | S ok |
| Guest role skips a host without a registry entry | unit | S ok |
| Node playbook ignores a host without a registry entry | unit | B ok |
| Registered host without a container ID | unit | B ok |
| Pre-deploy snapshot is written | unit | S ok |
| Service playbooks run the snapshot role before the service role | unit | S ok |
| First deploy without a database | unit | S ok |
| Failed snapshot fails the run | unit | S ok |
| Guest keeps the newest 10 pre-deploy snapshots | unit | S ok |
| Re-run without a version change still snapshots | manual | post-merge deploy, unit 6 |
| Metadata of a migrated database | unit | S ok |
| Database without schema_migrations | unit | S ok |
| Release version unknown | unit | S ok |
| Metadata travels with the snapshot to the node | unit | B ok |
| Nightly run collects every registered guest | unit | B ok |
| New pre-deploy snapshots are copied once | unit | B ok |
| One guest fails, the others still run | unit | B ok |
| Registered database missing in the guest | unit | S ok, B ok |
| Node disk full | unit | B ok |
| Timer runs the job daily on proxmox1 | manual | post-merge, unit 6 |
| Intact snapshot is kept | unit | B ok |
| Corrupt snapshot is discarded | unit | B ok |
| Daily rotation keeps the newest 14 | unit | B ok |
| Pre-deploy rotation keeps the newest 10 | unit | B ok |
| Pre-restore rotation keeps the newest 10 | unit | B ok |
| Fewer than 14 present | unit | B ok |
| Failed run deletes nothing | unit | B ok |
| All services succeeded | unit | B ok |
| A service failed | unit | B ok |
| healthchecks.io unreachable | unit | B ok |
| Ping URL unset | unit | B ok |
| Success ping arrives | manual | post-merge, unit 6 |
| Job never runs | manual | configured by Rue on healthchecks.io |
| Snapshot metadata is shown first | unit | B ok (test covers locate; playbook ordering locate-before-stop seen in restore playbook lines 40-66, not tested) |
| Snapshot name not found | unit | B ok |
| Current database is saved before the restore | unit | B ok |
| Restore ends with a healthy service | manual | post-merge drill, unit 6 |
| Restore leaves an unhealthy service | manual | not drilled |
| The deploy never runs the node playbook | unit | B ok |
| Check-mode run on proxmox1 | manual | Gate 2, unit 5 |
| Check-mode run of the service playbooks | manual | Gate 2, unit 5 |
| Onboarding a new service from the docs | manual | read docs/backups.md at Gate 2 |
| CLAUDE.md requires registration | manual | read .claude/CLAUDE.md at Gate 2 |
| Script change runs its fixture tests | unit | proof.sh --all prints PASS: sqlite-snapshot fixtures and PASS: sqlite-backup fixtures |

Gaps (tests for behaviour with no scenario in the delta spec; none of these names appears in a `#### Scenario:` heading):
- "Restore playbook refuses --check": B ok, behaviour not in spec
- "Role rejects a database path without .db suffix": S ok, behaviour not in spec
- "Registered database path without .db suffix": ok, behaviour not in spec
- "pre-restore without a container ID fails": B ok, spec only gives the `pre-restore <host> <ctid>` form and no failure scenario

## Manual checklist

- Check-mode run of node playbook against proxmox1 (task 5.x)
- Check-mode run of life-manager.yml and rues-arcade.yml (task 5.x)
- Read docs/backups.md onboarding section and the .claude/CLAUDE.md registration rule
- Post-merge (6.x): timer enabled on proxmox1, manual start lands both snapshots, success ping on healthchecks.io, restore drill on rues-arcade01, re-run deploy writes a new pre-deploy snapshot
- healthchecks.io missing-ping alert configured by Rue; unhealthy-restore message not drilled

## Diffstat (round 3)

 40 files changed, 2485 insertions(+) (40 files; top: scripts/tests/sqlite-backup.sh 497, scripts/tests/sqlite-snapshot.sh 271, spec.md 265, design.md 179, docs/backups.md 137)

## Screenshots

none
