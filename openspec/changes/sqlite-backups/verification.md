verified-at: dbb34f9

## Layer 1 (scripts/proof.sh --all, green)

```
PASS: sqlite-snapshot fixtures
PASS: sqlite-backup fixtures
PASS: check runner role has no deploy credentials
PASS: retired key path
proof: 24 sensor(s), 0 failed
```

## Layer 2 coverage

Evidence: `ok: Scenario: <title>` lines from scripts/tests/sqlite-snapshot.sh (S) and scripts/tests/sqlite-backup.sh (B), each run directly 3 times at dbb34f9, 6/6 rc 0, no non-ok lines, no flake. Every `Scenario:` name in the tests exists in the spec; every unit scenario has its test.

| Scenario | proof | Evidence |
|---|---|---|
| Life-Manager and Rues-Arcade are registered | unit | S ok |
| Guest role skips a host without a registry entry | unit | S ok |
| Node playbook ignores a host without a registry entry | unit | B ok |
| Registered host without a container ID | unit | B ok |
| Registered database path without .db suffix | unit | B ok |
| Role rejects a database path without .db suffix | unit | S ok |
| Pre-deploy snapshot is written | unit | S ok |
| Service playbooks run the snapshot role before the service role | unit | S ok |
| First deploy without a database | unit | S ok |
| Failed snapshot fails the run | unit | S ok |
| Guest keeps the newest 10 pre-deploy snapshots | unit | S ok |
| Re-run without a version change still snapshots | manual | manual (Gate 2 / post-merge checklist) |
| Metadata of a migrated database | unit | S ok |
| Database without schema_migrations | unit | S ok |
| Release version unknown | unit | S ok |
| Metadata travels with the snapshot to the node | unit | B ok |
| Nightly run collects every registered guest | unit | B ok |
| New pre-deploy snapshots are copied once | unit | B ok |
| One guest fails, the others still run | unit | B ok |
| Registered database missing in the guest | unit | S ok + B ok |
| Node disk full | unit | B ok |
| Timer runs the job daily on proxmox1 | manual | manual (Gate 2 / post-merge checklist) |
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
| Success ping arrives | manual | manual (Gate 2 / post-merge checklist) |
| Job never runs | manual | manual (Gate 2 / post-merge checklist) |
| Snapshot metadata is shown first | unit | B ok |
| Snapshot name not found | unit | B ok |
| Current database is saved before the restore | unit | B ok |
| pre-restore without a container ID fails | unit | B ok |
| Restore playbook refuses --check | unit | B ok |
| Restore of the oldest pre-restore snapshot | unit | B ok |
| Failed restore brings the unit back | unit | B ok |
| Restore ends with a healthy service | manual | manual (Gate 2 / post-merge checklist) |
| Restore leaves an unhealthy service | manual | manual (Gate 2 / post-merge checklist) |
| The deploy never runs the node playbook | unit | B ok |
| Check-mode run on proxmox1 | unit | B ok |
| Check-mode run of the service playbooks | manual | manual (Gate 2 / post-merge checklist) |
| Onboarding a new service from the docs | manual | manual (Gate 2 / post-merge checklist) |
| CLAUDE.md requires registration | manual | manual (Gate 2 / post-merge checklist) |
| Script change runs its fixture tests | unit | proof.sh --all prints PASS: sqlite-snapshot fixtures and PASS: sqlite-backup fixtures |

Gaps: none

Notes:
- "Check-mode run on proxmox1" has a unit part (B ok, local fixture run) and a manual part (real node, Gate 2, unit 5).
- Extra tests outside the spec (not counted): daily keeps only the newest snapshot (S), list pre-deploy prints basenames (S), Restore with an unknown snapshot name lists the available snapshots (B).
- The sqlite-backup fixtures depend on the environment: ansible-playbook needs a vault password file (see ansible.cfg); a clean HOME makes 10 scenarios fail, including "The deploy never runs the node playbook". CI provides a dummy file (ci.yml), so it is not affected.

## Manual checklist

- Check-mode run of the node playbook against proxmox1 (task 5.x)
- Check-mode run of life-manager.yml and rues-arcade.yml (task 5.x)
- Read docs/backups.md onboarding section and the .claude/CLAUDE.md registration rule
- Post-merge (6.x): timer enabled on proxmox1, manual start lands both snapshots, success ping on healthchecks.io, restore drill on rues-arcade01, re-run deploy writes a new pre-deploy snapshot
- healthchecks.io missing-ping alert configured by Rue; unhealthy-restore message not drilled

## Diffstat

 41 files changed, 2899 insertions(+), 1 deletion(-)

## Screenshots

none

## Review

Four fresh-context review rounds (Layer 3) plus three fixer rounds and one cleanup round. Correctness bugs found by review: 5 (all fixed with red-first tests); no weakened tests in any round.

| Round | Finding | Resolution |
|---|---|---|
| 1 | 5 weak tests (guest role skip relied on check-mode semantics; FAILED reason; restore call order; preflight-before-install; deploy-targets never exercised) | Strengthened, each reviewer mutant red (9480623) |
| 2 | 3 weak tests (partial file on failed snapshot; newest migration; node play `hosts:`) | Strengthened (2df3e08) |
| 2 | proof trigger missed sqlite_restore.yml / deploy-targets.sh | Trigger extended (2df3e08) |
| 2 | Restore crashed under --check | Restore refuses --check with a clear message; scenario added (2df3e08) |
| 2 | Two sources for the container ID | `pre-restore <host> <ctid>` takes the live inventory ctid (2df3e08) |
| 2 | Registry paths not ending in .db broke restore | Preflight asserts in both roles, documented (2df3e08) |
| 3 | Node playbook --check failed on a fresh proxmox1 (timer unit missing) | Check-mode tolerance for "unit not found" only (a6daff9, narrowed in dbb34f9) |
| 3 | Typo'd snapshot name didn't list available snapshots | `locate` runs before the name assert (a6daff9) |
| 3 | Pre-restore rotation could delete the snapshot being restored | `pre-restore` protects the chosen snapshot (a6daff9) |
| 3 | Rescue left the service stopped | Rescue starts the unit again (a6daff9) |
| 3 | Multi-DB host: rollback message could name the wrong DB's snapshot | Name matched by stem (a6daff9) |
| 4 | 2 weak tests (playbook passes protect arg; rescue really starts unit), naming gaps, broad check-mode ignore | Strengthened, renamed, narrowed to "Could not find the requested service" (dbb34f9) |

Accepted, not changed:
- Fixture suites need `~/.config/homelab/vault_pass` (ansible.cfg `vault_password_file`); in a clean HOME 10 scenarios fail with a bare `test 1 -eq 0`. CI writes a dummy vault file, so CI is unaffected. Same precondition as the repo's other ansible-based tests.
- `write_meta` reading the snapshot vs the live DB is not distinguishable with the stub (byte-identical copy); outside every scenario's THEN.

## Live dry runs (Gate 2 evidence, unit 5)

- 5.3 `ansible-playbook --check --diff` of `02_SERVICES/life-manager.yml` and `rues-arcade.yml` from the workstation at 3c993f1 (rendered inventory via `scripts/fetch-inventory.sh`): both exit 0, `ok=36 changed=4 unreachable=0 failed=0 skipped=12`. The 4 would-change tasks are exactly the sqlite_snapshot ones: apt `sqlite3` (only new package), snapshot script, config (SERVICE / RELEASE_LINK / SNAPSHOT_DIR=/var/backups/sqlite-snapshot / KEEP_PRE_DEPLOY=10 / DATABASE=/var/lib/<svc>/<svc>.db), snapshot dir. `.db` assert ok; the pre-deploy snapshot task is skipped in check mode (command task), so the snapshot itself is only proven after merge (6.2).
- 5.2 node playbook `--check` on proxmox1: pending (needs 5.1, the vaulted ping URL).
