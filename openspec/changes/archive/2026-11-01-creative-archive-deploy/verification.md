verified-at: 565f1c7

## Layer 1: `scripts/proof.sh --all` (green, exit 0)

```
PASS: no Tailscale auth key in the repo
PASS: retired key path
proof: 30 sensor(s), 0 failed
```

Includes `PASS: terraform fmt`, `terraform validate`, `tflint`, `checkov`, `ansible-lint`, `syntax-check ansible/playbooks/02_SERVICES/creative-archive.yml`, `workflow triggers`, `sqlite-snapshot fixtures`, `sqlite-backup fixtures`, `Regression: arcade shares IP with check container`.

## Layer 2: spec coverage

Unit evidence is `scripts/tests/sqlite-snapshot.sh` / `sqlite-backup.sh` `ok:` lines (re-run) plus named PASS lines of the green proof. One-shots were re-run by the verifier at 565f1c7.

| Scenario | proof | Evidence |
|---|---|---|
| Terraform sensors stay green with the new guest | unit | proof: PASS terraform fmt / validate / tflint / checkov / Regression: arcade shares IP ✓ |
| The address does not collide | unit | proof: `PASS: Regression: arcade shares IP with check container` ✓ |
| Host vars pass lint | unit | proof: `PASS: ansible-lint`, `PASS: sqlite-snapshot fixtures` ✓ |
| The role passes lint inside its playbook | unit | proof: `PASS: ansible-lint`, `PASS: syntax-check .../creative-archive.yml` ✓ |
| Workflow checks stay green (unit part) | unit + manual (CI on PR) | proof: `PASS: workflow triggers` ✓; CI check on the PR is post-merge/PR |
| Creative-Archive is registered | unit | sqlite-snapshot.sh `ok: Scenario: Creative-Archive is registered` ✓ |
| Rues-Cooking-Hub is registered | unit | `ok: Scenario: Rues-Cooking-Hub is registered` ✓ |
| The Creative-Archive playbook runs the snapshot role before its service role | unit | `ok:` line with that name ✓ |
| The Rues-Cooking-Hub playbook runs the snapshot role before its service role | unit | `ok:` line with that name ✓ |
| Life-Manager and Rues-Arcade are registered; Guest role skips a host without a registry entry; Role rejects a database path without .db suffix; Service playbooks run the snapshot role before the service role; Pre-deploy snapshot is written; First deploy without a database; Failed snapshot fails the run; Guest keeps the newest 10 pre-deploy snapshots | unit | sqlite-snapshot.sh `ok:` lines with those names ✓ |
| Node playbook ignores a host without a registry entry; Registered host without a container ID; Registered database path without .db suffix | unit | sqlite-backup.sh `ok:` lines with those names ✓ |
| The registry entry matches the role's paths | unit + manual | `ok: Scenario: Creative-Archive is registered` ✓; python check: release_link `/opt/creative-archive/current`, service/owner/group `creative-archive`, unit, databases, mode `0640`, healthz_url ✓ |
| The playbook applies the roles in order | unit + manual | `ok:` playbook-order line ✓; python: 1 play, hosts `creative_archive`, become True, roles `['common','nodejs','nginx','sqlite_snapshot','creative_archive']` ✓ |
| creative-archive01 is declared with the agreed identity | manual (diff review) | tfvars lines 89-99: `"creative-archive01" = {`, `192.168.0.229/24`, groups, tags, cores 2, memory 4096, swap 512, disk_gb 16, no vmid, comment names `02_SERVICES/creative-archive.yml` ✓ |
| The generated inventory is not edited | manual (one-shot) | `git diff --name-only origin/main...HEAD -- ansible/inventory/00-terraform.yml` and `git ls-files` both print nothing ✓ |
| The pin is one plain line the bump job can edit / The Creative-Archive pin line is bumpable | manual (one-shot) | `rg -c '^creative_archive_version: '` prints `1`; line is `creative_archive_version: v0.1.0` (cat -A: no trailing text) ✓ |
| nginx proxies to the service port | manual (python) | enabled True, backend 127.0.0.1, port `{{ creative_archive_port }}`, tz Europe/Berlin, smoke Host `{{ nginx_server_name }}` ✓ |
| No cooking-hub name remains in the role | manual (one-shot) | `rg -i 'cooking\|rues' ansible/roles/creative_archive` empty (rc 1); defaults line 12 `creative_archive_version: v0.1.0` ✓ |
| The artifact URL names the Creative-Archive release | manual (one-shot) | `ansible localhost -m debug -a "msg={{ creative_archive_artifact_url }}" -e @defaults/main.yml` -> `https://github.com/Rue-Asha/Creative-Archive/releases/download/v0.1.0/creative-archive-0.1.0.tgz`; checksum is inline `"sha256:{{ creative_archive_artifact_url }}.sha256"` in fetch.yml (no separate variable) ✓ |
| The environment file carries exactly the agreed variables | manual (one-shot) | env.j2 sets HOST, PORT, NODE_ENV, DATABASE_PATH, PROTOCOL_HEADER, BODY_SIZE_LIMIT only; defaults 127.0.0.1, 3000, production, db path, x-forwarded-proto, 17M ✓ |
| The test switch is never set | manual (one-shot) | `rg -n CREATIVE_ARCHIVE_TEST ansible/` empty (rc 1) ✓ |
| The role holds no secret | manual (one-shot) | `fd` lists no vault.yml; `rg 'vault\|password\|token'` empty (rc 1) ✓ |
| The tarball's top-level directory is stripped | manual (diff review) | fetch.yml:61 `extra_opts: [--strip-components=1]`; fetch.yml identical to rues_cooking_hub after renaming ✓ |
| A checksum mismatch fails before current flips | manual (diff review) | fetch.yml `checksum:` line 38; identical to cooking-hub after renaming ✓ |
| A failed smoke check rolls back | manual (diff review) | verify.yml and main.yml identical to cooking-hub after renaming; verify imported before prune ✓ |
| nginx is never stricter than the app | manual (one-shot) | host vars line 15 `18m`; defaults line 38 `17M` ✓ |
| Changing the limit restarts the service | manual (diff review) | config.yml `notify: Restart creative-archive`; handler of that name; config/handlers identical to cooking-hub after renaming ✓ |
| No shared role changes | manual (one-shot) | `git diff --name-only origin/main...HEAD -- roles/nginx nodejs common sqlite_snapshot` prints nothing ✓ |
| The merge diff selects the new playbook | manual (one-shot) | with throwaway inventory (removed): `scripts/deploy-targets.sh origin/main HEAD` -> only `ansible/playbooks/02_SERVICES/creative-archive.yml`; `scripts/deploy-targets.sh creative-archive` -> same path ✓ |
| deploy-targets.sh is unchanged | manual (one-shot) | `git diff --name-only origin/main...HEAD -- scripts/` -> only `scripts/tests/sqlite-snapshot.sh` ✓ |
| The dispatch list offers the Creative Archive | manual (diff review) | deploy.yml diff is the single added line `- creative-archive` after `- rues-cooking-hub` ✓ |
| Every doc names the new service | manual (one-shot) | `rg -l` lists README.md, docs/backups.md, docs/release-bump.md, role README, .claude/CLAUDE.md; `rg -i cooking` role README empty ✓ |
| The Specs line points at the new capability | manual (one-shot) | `rg -c 'Before changing creative-archive, read ...'` prints `1` ✓ |
| docs/backups.md names Creative-Archive | manual (one-shot) | line 3: "Life-Manager, Rues-Arcade, Rues-Cooking-Hub and Creative-Archive each keep their data..." ✓ |
| The runbook lists the steps in order | manual (doc review, Gate 2) | role README "First rollout": 8 steps in spec order, ⚠ on merge, approve infrastructure, backup run; `plan` job named as only plan location; accepted first-bump failure noted ✓ (prose for Gate 2) |
| A stale host key would block the apply | manual (doc review) | README step 1 names `ssh-keygen -F`/`-R` and the `tf-ci.sh apply` keyscan reason ✓ |
| No rollout step is a task | manual (plan review, Gate 1) | tasks.md has no merge/approve/plan/apply/playbook-on-host/tag task; only 1.8 (evidence run, local) is unchecked, which this verification covers ✓ |
| The first Creative-Archive bump fails before the merge | manual (observed on v0.1.0 release run) | post-merge/external; checklist |
| A Creative-Archive release after the merge opens a bump PR | manual (post-merge) | checklist |
| The runner plan shows exactly one new container | manual (post-merge) | checklist |
| creative-archive01 chains to proxmox_guest | manual (post-merge) | checklist |
| Merging before the tag fails the first deploy | manual (procedure) | README step 2 documents it; checklist |
| The first deploy comes up healthy | manual (post-merge) | checklist |
| A 16 MiB photo uploads | manual (post-merge) | checklist |
| The first deploy runs the new playbook once | manual (post-merge) | checklist |
| Re-run without a version change still snapshots | manual (post-merge) | checklist |
| The Creative-Archive database joins the nightly backup | manual (post-merge) | checklist |

No scenario lacks a proof line; no gaps.

## Manual post-merge checklist

Pre-merge:
1. On `runner01`: `ssh-keygen -F 192.168.0.229` finds nothing; otherwise `ssh-keygen -R 192.168.0.229` first.
2. Tag `v0.1.0` exists in `Rue-Asha/Creative-Archive` with `creative-archive-0.1.0.tgz` and `.sha256` (merging earlier fails the first deploy at fetch).

Rollout:
3. ⚠ Merge the PR (triggers plan, approval, apply, deploy).
4. Read the `plan` job log of `deploy.yml`: exactly one create `module.lxc["creative-archive01"]`, nothing else; then ⚠ approve `infrastructure`.
5. `deploy` job lists `02_SERVICES/creative-archive.yml` once and is green; `curl -i http://192.168.0.229/healthz` answers 200; `/opt/creative-archive/current/.deployed_version` reads `v0.1.0`; `creative-archive.service` active.
6. Re-run without a version change: the pre-deploy snapshot is still written (post-merge CI deploy).
7. Workstation: `scripts/fetch-inventory.sh`, then `ansible-inventory --graph` shows `creative-archive01` under `creative_archive` -> `lxc_container_proxmox` -> `proxmox_guest` with an `lxc_ctid`.
8. Workstation: `ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml --check`, then ⚠ without `--check`.
9. Next morning: `journalctl -u homelab-sqlite-backup.service` on proxmox1 logs `creative-archive01: ok`; `/var/backups/homelab/creative-archive01/daily/` holds `creative-archive-<stamp>.db` plus `.meta`.
10. Upload a ~16 MiB photo via `http://192.168.0.229`: no 413, app accepts.
11. CI on the PR: `security-baseline / workflow-lint` green.
12. App's `v0.1.0` bump job fails on the missing file (accepted). A later tag opens `chore(creative-archive): bump to <tag>` changing only `creative_archive_version`.

## Diffstat

```
 .claude/CLAUDE.md                                  |   1 +
 .github/workflows/deploy.yml                       |   1 +
 README.md                                          |   2 +
 .../host_vars/creative-archive01/vars.yml          |  27 +++
 ansible/playbooks/02_SERVICES/creative-archive.yml |  11 ++
 ansible/roles/creative_archive/README.md           | 132 +++++++++++++
 ansible/roles/creative_archive/defaults/main.yml   |  54 ++++++
 ansible/roles/creative_archive/handlers/main.yml   |   7 +
 ansible/roles/creative_archive/meta/main.yml       |  25 +++
 ansible/roles/creative_archive/tasks/config.yml    |  10 +
 .../roles/creative_archive/tasks/directories.yml   |  21 ++
 ansible/roles/creative_archive/tasks/fetch.yml     |  81 ++++++++
 ansible/roles/creative_archive/tasks/main.yml      |  31 +++
 ansible/roles/creative_archive/tasks/prune.yml     |  23 +++
 ansible/roles/creative_archive/tasks/release.yml   |  24 +++
 ansible/roles/creative_archive/tasks/service.yml   |  17 ++
 ansible/roles/creative_archive/tasks/user.yml      |  17 ++
 ansible/roles/creative_archive/tasks/verify.yml    |  51 +++++
 .../templates/creative-archive.service.j2          |  25 +++
 ansible/roles/creative_archive/templates/env.j2    |   8 +
 docs/backups.md                                    |   2 +-
 docs/release-bump.md                               |   1 +
 .../changes/creative-archive-deploy/.openspec.yaml |   2 +
 openspec/changes/creative-archive-deploy/flow.yaml |   6 +
 .../changes/creative-archive-deploy/proposal.md    |  79 ++++++++
 openspec/changes/creative-archive-deploy/scope.md  |  63 ++++++
 .../specs/creative-archive/spec.md                 | 213 +++++++++++++++++++++
 .../specs/release-bump/spec.md                     |  20 ++
 .../specs/sqlite-backups/spec.md                   | 105 ++++++++++
 openspec/changes/creative-archive-deploy/tasks.md  |  19 ++
 scripts/tests/sqlite-snapshot.sh                   |  30 +++
 terraform/environments/homelab/hosts.auto.tfvars   |  12 ++
 32 files changed, 1119 insertions(+), 1 deletion(-)
```

screenshots: none

## Review

Fresh-context reviewer (opus), diff `origin/main...flow/creative-archive-deploy`: no findings in any category (weakened tests, weak tests, spec mismatch, correctness). The test-only diff is `scripts/tests/sqlite-snapshot.sh` (+30, -0); the four new checks read the real host_vars and playbooks. The role matches `rues_cooking_hub` after renaming, apart from the 17M body limit and the README. Process note: task 1.8 (evidence run, no commit) was unticked; the orchestrator ticked it after the verifier re-ran the same commands (round 1, no gaps).
