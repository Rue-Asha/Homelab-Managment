verified-at: 1cc3387

## Layer 1: scripts/proof.sh --all (green, exit 0)

```
PASS: life-manager-proton fixtures
PASS: check runner role has no deploy credentials
PASS: no Tailscale auth key in the repo
PASS: retired key path
proof: 28 sensor(s), 0 failed
```

Sensor count: 28 (warm `.terraform` cache; the conditional `terraform init` sensor does not run).

Per-scenario lines come from running `scripts/tests/life-manager-proton.sh` directly (exit 0, 18 `ok: Scenario: ...` lines (21 scenarios minus 3 manual), no FAIL).

## Layer 2: coverage

| Scenario | proof | Evidence |
|---|---|---|
| The pinned binary is installed | unit | life-manager-proton.sh "Scenario: The pinned binary is installed" ok |
| Version, URL, sha256 and bin path are role defaults | unit | "Scenario: Version, URL, sha256 and bin path are role defaults" ok |
| A second run changes nothing | unit | "Scenario: A second run changes nothing" ok |
| A checksum mismatch fails the play before the env is touched | unit | "Scenario: A checksum mismatch fails the play before the env is touched" ok |
| The flag off downloads and removes nothing | unit | "Scenario: The flag off downloads and removes nothing" ok |
| A non-x86_64 host fails with a message naming the architecture | unit | "Scenario: A non-x86_64 host fails with a message naming the architecture" ok |
| The real download verifies on life-manager01 | manual | post-merge checklist |
| The flag on adds exactly the three Proton lines | unit | "Scenario: The flag on adds exactly the three Proton lines" ok |
| The flag off renders today's file byte for byte | unit | "Scenario: The flag off renders today's file byte for byte" ok |
| An env change restarts the service once | unit | "Scenario: An env change restarts the service once" ok |
| The session directories are created owner-only | unit | "Scenario: The session directories are created owner-only" ok |
| An existing session survives a run | unit | "Scenario: An existing session survives a run" ok |
| A missing session prints the login command and the play succeeds | unit | "Scenario: A missing session prints the login command and the play succeeds" ok |
| A present session prints no warning | unit | "Scenario: A present session prints no warning" ok |
| Check mode still reports the missing session | unit | "Scenario: Check mode still reports the missing session" ok |
| The session check cannot fail the play or trigger a rollback | unit | "Scenario: The session check cannot fail the play or trigger a rollback" ok |
| The warning shows in the real deploy log | manual | post-merge checklist |
| life-manager01 enables the flag | unit | "Scenario: life-manager01 enables the flag" ok |
| The README holds the variables and the login runbook | unit | "Scenario: The README holds the variables and the login runbook" ok |
| Login and sync work end to end | manual | post-merge checklist |
| Changing the role triggers the fixtures | unit | life-manager-proton.sh "Scenario: Changing the role triggers the fixtures" ok; proof --all `PASS: life-manager-proton fixtures` |

Gaps: none.

## Manual checklist (post-merge; task 1.7 dry run was skipped, no go from Rue)

- After the first deploy: `/usr/local/bin/proton` exists on life-manager01, `proton --version` reports v5.1.0, deploy run green.
- First deploy log of `life-manager.yml` on runner01 shows `Proton login needed` with the command, run green.
- Run the reported login command on life-manager01, re-run the deploy (no warning), open `/sync`, press "Sync now", events appear in Proton Calendar.

## Diffstat (origin/main...flow/life-manager-proton)

```
 .../inventory/host_vars/life-manager01/vars.yml    |   1 +
 ansible/roles/life_manager/README.md               |  35 +-
 ansible/roles/life_manager/defaults/main.yml       |  11 +
 ansible/roles/life_manager/tasks/main.yml          |   5 +
 ansible/roles/life_manager/tasks/proton.yml        |  44 ++
 ansible/roles/life_manager/templates/env.j2        |   5 +
 openspec/changes/life-manager-proton/* (6 files)   | 267 +
 scripts/proof.sh                                   |   8 +
 scripts/tests/life-manager-proton.sh               | 486 +++++
 15 files changed, 927 insertions(+), 1 deletion(-)
```

Screenshots: none
