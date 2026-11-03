verified-at: 4382e14

# Verification

## Layer 1: `scripts/proof.sh --all` (own run, green)

```
PASS: terraform fmt / terraform validate / tflint / checkov / ansible-lint
PASS: syntax-check ansible/playbooks/02_SERVICES/notes-archive.yml (and the other 11 playbooks)
PASS: collection pins
PASS: workflow triggers
PASS: deploy-targets fixtures
PASS: Regression: arcade shares IP with check container
PASS: unique-hosts fixtures
PASS: sqlite-snapshot fixtures
PASS: sqlite-backup fixtures
...
proof: 32 sensor(s), 0 failed
```

`scripts/tests/sqlite-snapshot.sh` run directly: exit 0, 22 `ok:` lines incl. `ok: Scenario: Notes-Archive is registered` and `ok: Scenario: The Notes-Archive playbook runs the snapshot role before its service role`. `git status` clean afterwards (no `.terraform.lock.hcl` change).

## Layer 2: coverage

Unit scenarios (proof sensors or `ok:` lines from my own runs):

| Scenario | proof | Evidence |
|---|---|---|
| Notes-Archive is registered | unit | `ok: Scenario: Notes-Archive is registered` ✓ |
| The Notes-Archive playbook runs the snapshot role before its service role | unit | `ok:` line ✓ |
| Creative-Archive / Rues-Cooking-Hub registered + playbook-order scenarios, Life-Manager and Rues-Arcade registered, Service playbooks run snapshot first | unit | matching `ok:` lines ✓ |
| Pre-deploy snapshot is written / First deploy without a database / Failed snapshot fails the run / Guest keeps the newest 10 / Guest role skips / Role rejects path without .db | unit | matching `ok:` lines ✓ |
| A WAL database is copied with the online backup | unit | `ok: Scenario: Pre-deploy snapshot is written` ✓ |
| Node playbook ignores a host without a registry entry; Registered database path without .db suffix | unit | covered by `PASS: sqlite-backup fixtures` (sqlite-backup.sh) ✓ |
| Registered host without a container ID; Registering before the first healthy deploy fails the nightly run (unit part) | unit | `PASS: sqlite-backup fixtures` ✓ (runbook-order part: see manual) |
| Terraform sensors stay green with the new guest | unit | PASS terraform fmt, validate, tflint, checkov, Regression: arcade shares IP ✓ |
| The address does not collide | unit | `PASS: unique-hosts fixtures`, `PASS: Regression: arcade shares IP with check container` ✓ |
| Host vars pass lint | unit | `PASS: ansible-lint`, `PASS: sqlite-snapshot fixtures` ✓ |
| The role passes lint inside its playbook | unit | `PASS: ansible-lint`, `PASS: syntax-check .../notes-archive.yml` ✓ |
| Workflow checks stay green | unit | `PASS: workflow triggers` ✓ (CI check on the PR is manual) |

Manual one-shots, run by me against the tip (outputs in scratchpad `v1/oneshots.log`):

| Scenario | proof | Evidence |
|---|---|---|
| notes-archive01 is declared with the agreed identity | manual | `git diff origin/main...HEAD -- terraform/`: one entry, `.231/24`, `notes_archive`, tags web+terraform, 2/4096/512/16, no vmid; only other change is the retropie01 comment ✓ |
| The retropie01 note records the moved address | manual | `rg notes-archive01` finds entry (l.103) + comment (l.133); `rg 'vmid += 231'` empty ✓ |
| The generated inventory is not edited | manual | `git diff --name-only` and `git ls-files` for 00-terraform.yml both empty ✓ |
| The pin is one plain line the bump job can edit / The Notes-Archive pin line is bumpable | manual | `rg -c` prints `1`; line is `notes_archive_version: v0.1.0` (no trailing space/comment, `cat -A`) ✓ |
| nginx proxies to the service port | manual | python: enabled True, host 127.0.0.1, port `{{ notes_archive_port }}`, tz Europe/Berlin, smoke headers `Host: {{ nginx_server_name }}` ✓ |
| The registry entry matches the role's paths | manual | python: databases/unit/release_link/service/owner/group as specced ✓ |
| The playbook applies the roles in order | manual | python: 1 play, hosts notes_archive, become True, roles common,nodejs,nginx,sqlite_snapshot,notes_archive ✓ |
| The release assets are public before the first tag (rg part) | manual | `rg 'token\|Authorization\|url_password' tasks/fetch.yml` empty ✓; README names public as precondition (step 2) ✓; curl is pre-merge, see checklist |
| No creative-archive name remains in the role | manual | `rg -i creative` empty; default `notes_archive_version: v0.1.0` found ✓ |
| The artifact URL names the Notes-Archive release | manual | ansible debug prints `https://github.com/Rue-Asha/Notes-Archive/releases/download/v0.1.0/notes-archive-0.1.0.tgz` ✓ (`.sha256` URL not separately printed) |
| The environment file carries exactly the agreed variables | manual | env.j2 sets HOST, PORT, NODE_ENV, DATABASE_PATH, PROTOCOL_HEADER, BODY_SIZE_LIMIT only; defaults 127.0.0.1/3000/production/x-forwarded-proto/17M ✓ (DB path default line not shown in rg; registry path matches) |
| Test routes and mockup photos stay off | manual | `rg 'NOTES_ARCHIVE_TEST\|MOCKUP_PHOTOS_DIR' ansible/` empty ✓ |
| The role holds no secret | manual | `fd` lists no vault.yml; `rg 'vault\|password\|token'` empty ✓ |
| No migrate task exists | manual | `rg -i migrat tasks/` empty; defaults comment and README (additive, new files only) present ✓ |
| The tarball's top-level directory is stripped | manual | tasks/fetch.yml identical to creative_archive after name mapping; `--strip-components=1` at l.61 ✓ |
| The WAL files can be written beside the database | manual | unit template differs from creative_archive only in Description (ReadWritePaths unchanged) ✓ |
| A checksum mismatch fails before current flips | manual | fetch.yml/main.yml identical to creative_archive after name mapping ✓ |
| A failed smoke check rolls back | manual | verify.yml/main.yml identical to creative_archive after name mapping ✓ |
| Changing the limit restarts the service | manual | config.yml and handlers identical to creative_archive after name mapping ✓ (live restart post-merge) |
| The nodejs role already satisfies Node 22.18 (diff part) | manual | `git diff --name-only ... ansible/roles/nodejs` empty ✓ |
| nginx is never stricter than the app | manual | `18m` (host vars l.15) vs `17M` (defaults l.38) ✓ |
| No shared role changes | manual | diff over nginx/nodejs/common/sqlite_snapshot empty ✓ |
| The merge diff selects the new playbook | manual | throwaway inventory: `scripts/deploy-targets.sh origin/main HEAD` prints exactly `ansible/playbooks/02_SERVICES/notes-archive.yml`; `deploy-targets.sh notes-archive` prints same; inventory removed, `git status` clean ✓ |
| deploy-targets.sh is unchanged | manual | `git diff --name-only origin/main...HEAD -- scripts/` lists only `scripts/tests/sqlite-snapshot.sh` ✓ |
| The dispatch list offers Notes-Archive | manual | diff is one added line `- notes-archive` after `- creative-archive` ✓ |
| The repo list names Notes-Archive | manual | last `- repo:` entry is `Rue-Asha/Notes-Archive` (l.24); `rg -c Notes-Archive docs/check-runner.md` = 2 ✓ |
| Every doc names the new service | manual | all five files listed; no `creative` in role README ✓ |
| docs/backups.md names Notes-Archive | manual | l.3 names it after Creative-Archive ✓ |
| docs/release-bump.md lists Notes-Archive | manual | row at l.94 directly after creative-archive row (l.93) ✓ |
| The runbook states the exposure | manual | README l.91-92: no auth, LAN IP + tailscale subnet router ✓ (no DNS/TLS sentence on those lines; read at Gate 2) |
| The runbook lists the steps in order | manual (doc review) | README "First rollout": ten steps present in order 1..10, ⚠ on 3, 4 (approve), 7, 8, 10, each names its scenario, `plan` job named as the only place for the plan ✓ |
| A stale host key would block the apply | manual (doc review) | README step 1 has `ssh-keygen -F` / `-R 192.168.0.231` and the tf-ci.sh keyscan reason ✓ |
| docs/backups.md / runbook order scenarios (The rendered inventory comes before the backup registration) | manual (doc review) | README: step 6 (fetch-inventory) precedes step 8 (sqlite_backup.yml); step 8 after healthy deploy ✓ |
| Re-run without a version change still snapshots | manual (post-merge) | on checklist |
| Remaining post-merge scenarios (see checklist) | manual (post-merge) | cannot be proven now |

Gaps: none. Not provable now: the post-merge and Gate-time scenarios on the checklist.

## Manual checklist for Rue

1. `ssh-keygen -F 192.168.0.231` on runner01 finds nothing, else `ssh-keygen -R 192.168.0.231` (A stale host key would block the apply).
2. Make `Rue-Asha/Notes-Archive` public; `curl -fsSIL` on `.../v0.1.0/notes-archive-0.1.0.tgz` and `.sha256` answer 200 without login (The release assets are public before the first tag; Merging before the tag fails the first deploy if skipped).
3. ⚠ Merge the PR (The first deploy runs the new playbook once).
4. Read the `plan` job: exactly one create, `module.lxc["notes-archive01"]`; then ⚠ approve `infrastructure` (The runner plan shows exactly one new container).
5. `deploy` job lists `02_SERVICES/notes-archive.yml` once; `curl -i http://192.168.0.231/healthz` answers 200 (The first deploy comes up healthy; Re-run without a version change still snapshots on a later re-run); `node --version` on the guest is v22.18.0 or later.
6. `scripts/fetch-inventory.sh`, `ansible-inventory --graph` shows `notes-archive01` under notes_archive, lxc_container_proxmox, proxmox_guest with `lxc_ctid` (notes-archive01 chains to proxmox_guest).
7. Only if step 5 failed for a missing tag: after publishing `v0.1.0`, ⚠ dispatch `deploy.yml` with playbook `notes-archive` (A first release equal to the pin goes live by dispatch; A first tag equal to the pin bumps nothing; A Notes-Archive release after the split-off opens a bump PR, needs the split-off release workflow).
8. After a healthy deploy: `ansible-playbook .../sqlite_backup.yml --check`, then ⚠ without `--check`.
9. Next morning proxmox1 nightly log shows `notes-archive01: ok` (The Notes-Archive database joins the nightly backup).
10. Upload a 16 MiB image in a browser at `http://192.168.0.231` (A 16 MiB image uploads); changing the limit restarts the service (live).
11. ⚠ Check runner: gh admin and fork-PR approval on `Rue-Asha/Notes-Archive`; `check_runner.yml --check`, then ⚠ without; runner online with label `homelab-check` (Registration without the fork-approval policy fails naming the repo; The Notes-Archive runner comes online).
12. CI on the PR is green (Workflow checks stay green, CI part).
13. Closer: `## Specs` line for notes-archive in `.claude/CLAUDE.md` at archive (The Specs line points at the new capability). Plan review at Gate 1 for "No rollout step is a task".

## Diffstat (git diff --stat origin/main...flow/notes-archive-deploy)

 .github/workflows/deploy.yml                       |   1 +
 README.md                                          |   2 +
 ansible/inventory/group_vars/check_runner/vars.yml |   1 +
 .../inventory/host_vars/notes-archive01/vars.yml   |  27 +++
 ansible/playbooks/02_SERVICES/notes-archive.yml    |  11 +
 ansible/roles/notes_archive/README.md              | 160 ++++++++++++
 ansible/roles/notes_archive/defaults/main.yml      |  54 +++++
 ansible/roles/notes_archive/handlers/main.yml      |   7 +
 ansible/roles/notes_archive/meta/main.yml          |  25 ++
 ansible/roles/notes_archive/tasks/config.yml       |  10 +
 ansible/roles/notes_archive/tasks/directories.yml  |  21 ++
 ansible/roles/notes_archive/tasks/fetch.yml        |  81 +++++++
 ansible/roles/notes_archive/tasks/main.yml         |  31 +++
 ansible/roles/notes_archive/tasks/prune.yml        |  23 ++
 ansible/roles/notes_archive/tasks/release.yml      |  24 ++
 ansible/roles/notes_archive/tasks/service.yml      |  17 ++
 ansible/roles/notes_archive/tasks/user.yml         |  17 ++
 ansible/roles/notes_archive/tasks/verify.yml       |  51 ++++
 ansible/roles/notes_archive/templates/env.j2       |   8 +
 .../templates/notes-archive.service.j2             |  25 ++
 docs/backups.md                                    |   6 +-
 docs/check-runner.md                               |   7 +-
 docs/release-bump.md                               |   1 +
 .../changes/notes-archive-deploy/.openspec.yaml    |   2 +
 openspec/changes/notes-archive-deploy/flow.yaml    |   7 +
 openspec/changes/notes-archive-deploy/proposal.md  |  93 +++++++
 openspec/changes/notes-archive-deploy/scope.md     |  65 +++++
 .../specs/notes-archive/spec.md                    | 267 +++++++++++++++++++++
 .../specs/release-bump/spec.md                     |  25 ++
 .../specs/sqlite-backups/spec.md                   | 130 ++++++++++
 .../split-off-notes-archive-ci.md                  |  17 ++
 openspec/changes/notes-archive-deploy/tasks.md     |  20 ++
 scripts/tests/sqlite-snapshot.sh                   |   2 +
 terraform/environments/homelab/hosts.auto.tfvars   |  15 +-
 34 files changed, 1246 insertions(+), 7 deletions(-)

Outside-scope check: every changed file is in the unit `files=` list or the change dir; all new files tracked. Screenshots: none.

## Review

Fresh-context reviewer, `git diff origin/main...flow/notes-archive-deploy`: no findings in WEAKENED TESTS, WEAK TESTS, SPEC MISMATCH or CORRECTNESS. It diffed the role against `creative_archive` with names replaced and found only wording differences.

Outside the categories, one note: `ansible/roles/notes_archive/defaults/main.yml` line 9 says "The repo is public, so there is no deploy key", but `Rue-Asha/Notes-Archive` is private today. Not fixed, on purpose: it is a comment inherited from the clone, no scenario depends on it, and it becomes true once the repo is public, which the README and runbook step 2 make a precondition for the first tag.
