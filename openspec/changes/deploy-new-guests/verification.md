verified-at: 5490e5b

## Layer 1 — proof (`scripts/proof.sh --all`, proof-full: none)

```
PASS: terraform fmt
PASS: terraform init
PASS: terraform validate
PASS: tflint
PASS: checkov
PASS: ansible-lint
PASS: syntax-check ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml
PASS: syntax-check ansible/playbooks/02_BASE_CONFIGURATION/deploy_runner.yml
PASS: syntax-check ansible/playbooks/03_SERVICES/life-manager.yml
PASS: syntax-check ansible/playbooks/03_SERVICES/pihole.yml
PASS: collection pins
PASS: workflow triggers
PASS: deploy-targets fixtures
PASS: plan-protected fixtures
PASS: retired key path
proof: 15 sensor(s), 0 failed
```

Fixture runner run directly (`scripts/tests/deploy-targets.sh`, exit 0): 37 `ok:` lines, none failed.

## Layer 2 — spec coverage

| Scenario | proof | Evidence |
|---|---|---|
| Version bump for one service | unit | `scripts/tests/deploy-targets.sh` › "version bump runs only its service" ✓ |
| Shared role changes | unit | `scripts/tests/deploy-targets.sh` › "shared role runs every playbook using it, incl. via meta deps" ✓ |
| Nothing deployable changed | unit | `scripts/tests/deploy-targets.sh` › "README and terraform deploy nothing" ✓ |
| Push history cannot be diffed | unit | `scripts/tests/deploy-targets.sh` › "zero before runs everything" ✓, "non-ancestor before runs everything" ✓ |
| Manual redeploy | unit + manual (dispatch wiring) | `scripts/tests/deploy-targets.sh` › "named playbook" ✓, "--all" ✓; dispatch wiring on the manual list |
| A merge adds a guest | manual (first live run: rebuild-pihole01) | manual list |
| No terraform change | manual (this change's own merge run) | manual list |
| Apply creates nothing | manual (live update-only apply) | manual list |
| Apply fails | manual (live failed apply) | manual list |
| A created guest selects its service playbook | unit | `scripts/tests/deploy-targets.sh` › "Scenario: A created guest selects its service playbook" ✓ |
| Created guest and diff selections are merged | unit | `scripts/tests/deploy-targets.sh` › "Scenario: Created guest and diff selections are merged" ✓ |
| A playbook selected twice runs once | unit | `scripts/tests/deploy-targets.sh` › "Scenario: A playbook selected twice runs once" ✓ |
| A created guest without a service playbook | unit | `scripts/tests/deploy-targets.sh` › "Scenario: A created guest without a service playbook" ✓ |
| A created runner is never deployed | unit | `scripts/tests/deploy-targets.sh` › "Scenario: A created runner is never deployed" ✓ |
| An unknown created host fails loudly | unit | `scripts/tests/deploy-targets.sh` › "Scenario: An unknown created host fails loudly" ✓ |
| An empty created list changes nothing | unit | `scripts/tests/deploy-targets.sh` › "Scenario: An empty created list changes nothing" ✓ |
| Created guests are refused outside the diff form | unit | `scripts/tests/deploy-targets.sh` › "Scenario: Created guests are refused outside the diff form (--all)" ✓, "(name)" ✓ |
| Proof runs the created-guest fixtures | unit (`scripts/proof.sh --all`) | proof › "PASS: deploy-targets fixtures" ✓; fixture output has an `ok:` line for all 8 created-guest scenarios ✓ |
| Reader checks what a new guest gets | manual (doc review at Gate 2) | manual list |

Gaps: none.

## Manual

- [ ] Manual redeploy: on GitHub, Actions › deploy › Run workflow with `pihole` (then `all`); the run selects that playbook (or every `03_SERVICES` playbook) and ignores `created`.
- [ ] A merge adds a guest: in the rebuild-pihole01 merge run, the `apply` job output `created` is `pihole01` and the `deploy` log shows `deploy-targets.sh --created pihole01 …` selecting `03_SERVICES/pihole.yml`, ending with its smoke check passing.
- [ ] No terraform change: in this change's own merge run, `apply` is skipped and `deploy` selects exactly what the `ansible/` diff selects (here: nothing, says so in the log).
- [ ] Apply creates nothing: on the next update-only apply, `created` is empty and `deploy` selects only the diff's playbooks.
- [ ] Apply fails: on a failed/rejected apply, no `deploy` job runs for that push (job condition unchanged in `.github/workflows/deploy.yml`).
- [ ] Reader checks what a new guest gets: read `docs/deploy-runner.md` — it says a created guest's service playbooks run in the same run, a bare guest gets none, and a recreated guest still needs `deploy_runner.yml`.

## Diffstat (`git diff --stat main...flow/deploy-new-guests`)

```
 .github/workflows/deploy.yml                       |  14 +-
 docs/deploy-runner.md                              |  17 ++-
 openspec/changes/deploy-new-guests/.openspec.yaml  |   2 +
 openspec/changes/deploy-new-guests/design.md       |  82 ++++++++++++
 openspec/changes/deploy-new-guests/flow.yaml       |   7 +
 openspec/changes/deploy-new-guests/proposal.md     |  61 +++++++++
 openspec/changes/deploy-new-guests/scope.md        |  65 +++++++++
 .../specs/continuous-deployment/spec.md            | 147 +++++++++++++++++++++
 openspec/changes/deploy-new-guests/tasks.md        |  15 +++
 scripts/deploy-targets.sh                          |  44 +++++-
 scripts/tests/deploy-targets.sh                    |  67 +++++++++-
 scripts/tf-ci.sh                                   |   8 +-
 12 files changed, 504 insertions(+), 25 deletions(-)
```

## Screenshots

none
