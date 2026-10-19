verified-at: 7298be3

## Layer 1: `scripts/proof.sh --all` (exit 0)

```
PASS: syntax-check ansible/playbooks/02_SERVICES/rues-cooking-hub.yml
PASS: collection pins
PASS: workflow triggers
PASS: deploy-targets fixtures
PASS: plan-protected fixtures
PASS: workflow-triggers fixtures
PASS: Regression: arcade shares IP with check container
PASS: unique-hosts fixtures
PASS: sqlite-snapshot fixtures
PASS: sqlite-backup fixtures
PASS: tailscale fixtures
PASS: life-manager-proton fixtures
PASS: check runner role has no deploy credentials
PASS: no Tailscale auth key in the repo
PASS: retired key path
proof: 29 sensor(s), 0 failed
exit 0
```

Also in the log: `PASS: terraform fmt`, `PASS: terraform validate`, `PASS: tflint`, `PASS: checkov`, `PASS: ansible-lint`. Working tree clean after the run.

## Layer 2: scenario coverage

Re-run one-shot commands ran in this worktree. Fixture scenarios were mapped by running `scripts/tests/*.sh` directly (proof.sh prints only the suite line).

### rues-cooking-hub

| Scenario | proof | Evidence |
|---|---|---|
| rues-cooking-hub01 is declared with the agreed identity | manual | diff of `hosts.auto.tfvars` read: all literals match, comment above, no vmid ✓ (Gate 2 diff review) |
| Terraform sensors stay green with the new guest | sensors | `PASS: terraform fmt`, `terraform validate`, `tflint`, `checkov`, `Regression: arcade shares IP with check container` ✓ |
| An address collision fails the proof | unit | `scripts/tests/unique-hosts.sh` "ok: duplicate ipv4 without vmids"; `PASS: unique-hosts fixtures` ✓ |
| The runner plan shows exactly one new container | manual (post-merge) | checklist |
| rues-cooking-hub01 chains to proxmox_guest | manual (post-merge) | checklist |
| No arcade name remains in the role | one-shot | `rg -i arcade ansible/roles/rues_cooking_hub` → no match (rc 1); `rg -n 'rues_cooking_hub_version: v0.1.0' …/defaults/main.yml` → line 12 ✓ |
| The role passes lint inside its playbook | sensors | `PASS: ansible-lint`, `PASS: syntax-check …/02_SERVICES/rues-cooking-hub.yml` ✓ |
| The artifact URL names the Cooking Hub release | one-shot | `ansible localhost -m debug -a "msg={{ rues_cooking_hub_artifact_url }}" -e @…/defaults/main.yml` → `https://github.com/Rue-Asha/Rues-Cooking-Hub/releases/download/v0.1.0/rues-cooking-hub-0.1.0.tgz`; checksum URL is `"{{ artifact_url }}.sha256"` (fetch.yml:38) ✓ |
| The tarball's top-level directory is stripped | one-shot | `rg strip-components tasks/fetch.yml` → `extra_opts: [--strip-components=1]` (line 61); fetch.yml differs from `rues_arcade` only by the rename (diff after sed) ✓ |
| A checksum mismatch fails before current flips | manual | fetch.yml:38 `get_url … checksum: "sha256:…"` same as arcade; not reproducible (Gate 2) |
| The first deploy comes up healthy | manual (post-merge) | checklist |
| The environment file carries the body size limit | one-shot | `rg` env.j2: line 7 `PROTOCOL_HEADER=…`, line 8 `BODY_SIZE_LIMIT={{ rues_cooking_hub_body_size_limit }}`; defaults `rues_cooking_hub_body_size_limit: 16M` ✓ |
| nginx does not answer 413 before the app decides | one-shot | `rg client_max_body host_vars/rues-cooking-hub01/vars.yml` → `nginx_client_max_body_size: 16m` (line 15); app `16M` ✓ |
| Changing the limit restarts the service | manual | `tasks/config.yml` template task has `notify: Restart rues-cooking-hub`; `handlers/main.yml` defines it ✓ (live restart post-merge) |
| A 15 MB photo uploads | manual (post-merge) | checklist |
| No shared role changes | one-shot | `git diff --name-only origin/main...HEAD -- ansible/roles/nginx ansible/roles/nodejs ansible/roles/common ansible/roles/sqlite_snapshot` → empty ✓ |
| The playbook applies the roles in order | one-shot | python/yaml: 1 play, `hosts: rues_cooking_hub`, `become: True`, roles `['common','nodejs','nginx','sqlite_snapshot','rues_cooking_hub']` ✓ |
| The merge diff selects the new playbook | one-shot | `scripts/deploy-targets.sh rues-cooking-hub` → `ansible/playbooks/02_SERVICES/rues-cooking-hub.yml`; range `deploy-targets.sh $(git merge-base origin/main HEAD) HEAD` with a throwaway fixture `00-terraform.yml` (gitignored, shaped like ansible.tf output, removed after) → only that path; `--created rues-cooking-hub01` same ✓ (note: needs the generated inventory, absent in a fresh worktree) |
| deploy-targets.sh is unchanged | one-shot | `git diff --name-only origin/main...HEAD -- scripts/` → empty ✓ |
| The first deploy runs the new playbook once | manual (post-merge) | checklist |
| The pin is one plain line the bump job can edit | one-shot | `rg -c '^rues_cooking_hub_version: ' …/vars.yml` → `1`; line `3:rues_cooking_hub_version: v0.1.0$` (cat -A: no trailing space/comment) ✓ |
| The registry entry matches the role's paths | one-shot | python yaml: databases `['/var/lib/rues-cooking-hub/rues-cooking-hub.db']`, unit `rues-cooking-hub.service`, release_link `/opt/rues-cooking-hub/current`, service/owner/group `rues-cooking-hub` ✓ |
| Host vars pass lint | sensor | `PASS: ansible-lint` ✓ |
| The dispatch list offers the Cooking Hub | one-shot | `git diff origin/main...HEAD -- .github/workflows/deploy.yml` → one added line `- rues-cooking-hub` after `rues-arcade` ✓ |
| Workflow checks stay green | sensor + manual | `PASS: workflow triggers` ✓; CI `security-baseline / workflow-lint` on the PR → checklist (post-PR) |
| Every doc names the new service | one-shot | `rg -l …` → README.md, docs/backups.md, docs/release-bump.md, ansible/roles/rues_cooking_hub/README.md (all four); `rg -i arcade` role README → none ✓ |
| The runbook lists the steps in order | manual | README "First rollout" at line 88, steps marked ⚠, accepted bump failure at line 122 (Gate 2 prose review) |
| A stale host key would block the apply | manual | README step 1 `ssh-keygen -F 192.168.0.228` / `-R` (line 94); pre-merge step on runner01 |
| Merging before the tag fails the first deploy | manual | procedure; README step order (Gate 2) |
| The database joins the nightly backup | manual (post-merge) | checklist |

### release-bump

| Scenario | proof | Evidence |
|---|---|---|
| The pin line is bumpable | one-shot | `rg -c '^rues_cooking_hub_version: '` → `1`, value `v0.1.0`, unquoted, no comment ✓ |
| A release after the merge opens a bump PR | manual (post-merge) | checklist |
| The first release's bump fails before the merge | manual | observed on the app repo's `v0.1.0` release run; script covered by the existing unit in Rue-Asha/ci (not run here) |

### sqlite-backups

| Scenario | proof | Evidence |
|---|---|---|
| Life-Manager and Rues-Arcade are registered | unit | `scripts/tests/sqlite-snapshot.sh` "ok: Scenario: Life-Manager and Rues-Arcade are registered"; `PASS: sqlite-snapshot fixtures` ✓ |
| Rues-Cooking-Hub is registered | one-shot | python yaml of host_vars `sqlite_backups`: unit `rues-cooking-hub.service`, owner `rues-cooking-hub`, db `/var/lib/rues-cooking-hub/rues-cooking-hub.db` ✓ |
| Guest role skips a host without a registry entry | unit | sqlite-snapshot.sh "ok: Scenario: Guest role skips a host without a registry entry" ✓ |
| Node playbook ignores a host without a registry entry | unit | sqlite-backup.sh "ok: Scenario: Node playbook ignores a host without a registry entry"; `PASS: sqlite-backup fixtures` ✓ |
| Registered host without a container ID | unit | sqlite-backup.sh "ok: Scenario: Registered host without a container ID" ✓ |
| Registered database path without .db suffix | unit | sqlite-backup.sh "ok: Scenario: Registered database path without .db suffix" ✓ |
| Role rejects a database path without .db suffix | unit | sqlite-snapshot.sh "ok: Scenario: Role rejects a database path without .db suffix" ✓ |
| Pre-deploy snapshot is written | unit | sqlite-snapshot.sh "ok: Scenario: Pre-deploy snapshot is written" ✓ |
| Service playbooks run the snapshot role before the service role | unit | sqlite-snapshot.sh "ok: Scenario: Service playbooks run the snapshot role before the service role" ✓ (covers the two old playbooks only) |
| The Rues-Cooking-Hub playbook runs the snapshot role before its service role | one-shot | python yaml role order `common, nodejs, nginx, sqlite_snapshot, rues_cooking_hub` ✓ |
| First deploy without a database | unit | sqlite-snapshot.sh "ok: Scenario: First deploy without a database" ✓ |
| Failed snapshot fails the run | unit | sqlite-snapshot.sh "ok: Scenario: Failed snapshot fails the run" ✓ |
| Guest keeps the newest 10 pre-deploy snapshots | unit | sqlite-snapshot.sh "ok: Scenario: Guest keeps the newest 10 pre-deploy snapshots" ✓ |
| Re-run without a version change still snapshots | manual (post-merge) | checklist |

No gaps: every scenario has a proof line and its sensor, fixture or command ran.

## Manual checklist

### pre-merge
- [ ] Gate 2: read the `hosts.auto.tfvars` diff against the agreed identity (192.168.0.228/24, 2c/4096/512/16G, tags, no vmid).
- [ ] Gate 2: read the role README "First rollout" prose (order, ⚠ marks, accepted first-bump failure).
- [ ] On `runner01`: `ssh-keygen -F 192.168.0.228` must print nothing; if it prints a key, `ssh-keygen -R 192.168.0.228`.
- [ ] `gh release view v0.1.0 -R Rue-Asha/Rues-Cooking-Hub` shows `rues-cooking-hub-0.1.0.tgz` and `.sha256`; merge only after the tag exists.
- [ ] On the PR: CI `security-baseline / workflow-lint` (actionlint) and `ci` are green.

### post-merge ⚠ (Rue)
- [ ] ⚠ Merge the PR (deploys).
- [ ] ⚠ Read the `plan` job log: one `create` for `module.lxc["rues-cooking-hub01"]`, nothing else; then approve `infrastructure`.
- [ ] Deploy job: "Playbooks to run" lists `02_SERVICES/rues-cooking-hub.yml` exactly once; job green.
- [ ] `curl -s -o /dev/null -w '%{http_code}\n' http://192.168.0.228/healthz` → 200; on the guest `cat /opt/rues-cooking-hub/current/.deployed_version` → `v0.1.0`; `systemctl is-active rues-cooking-hub.service` → active.
- [ ] `scripts/fetch-inventory.sh && ansible-inventory --graph` → `rues-cooking-hub01` under `rues_cooking_hub` → `lxc_container_proxmox` → `proxmox_guest`; `ansible-inventory --host rues-cooking-hub01` shows `ansible_host` 192.168.0.228 and `lxc_ctid`.
- [ ] Open `http://192.168.0.228` in a browser and upload a ~15 MB photo: no 413, no app rejection.
- [ ] ⚠ `ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml --check`, then the same without `--check` (registers the DB with the nightly job); next night proxmox1 logs `rues-cooking-hub01: ok` and `/var/backups/homelab/rues-cooking-hub01/daily/` holds `rues-cooking-hub-<stamp>.db` + `.meta`.
- [ ] Re-run `gh workflow run deploy.yml -f playbook=rues-cooking-hub` (⚠ deploys) and confirm a second pre-deploy snapshot on the guest, same version.
- [ ] Cut a Rues-Cooking-Hub tag newer than v0.1.0: the `bump` job opens `chore(rues-cooking-hub): bump to <tag>` changing only `rues_cooking_hub_version`.
- [ ] Accepted: the app repo's `v0.1.0` bump job fails with `bump-pin: <file>: file not found`; nothing to repair.

## Cross-cutting facts

- (a) ✓ `git diff --name-only origin/main...HEAD -- scripts/ ansible/roles/nginx ansible/roles/nodejs ansible/roles/common ansible/roles/sqlite_snapshot` → empty.
- (b) ✓ `rg -i arcade ansible/roles/rues_cooking_hub` → no matches (rc 1).
- (c) ✓ `scripts/deploy-targets.sh $(git merge-base origin/main HEAD) HEAD` → only `ansible/playbooks/02_SERVICES/rues-cooking-hub.yml` (with a temporary fixture `00-terraform.yml`, removed; without any inventory the script's `ansible-playbook --list-hosts` call fails, as it does in any fresh worktree).
- (d) ✓ artifact URL `https://github.com/Rue-Asha/Rues-Cooking-Hub/releases/download/v0.1.0/rues-cooking-hub-0.1.0.tgz` (ansible debug).
- (e) ✓ checksum URL `<artifact URL>.sha256` = `https://github.com/Rue-Asha/Rues-Cooking-Hub/releases/download/v0.1.0/rues-cooking-hub-0.1.0.tgz.sha256` (from `fetch.yml:38`, `checksum: "sha256:{{ rues_cooking_hub_artifact_url }}.sha256"`; not fetched).
- (f) ✓ `terraform fmt -check -recursive terraform/` → rc 0, no output.

## Diffstat vs origin/main

```
 31 files changed, 1088 insertions(+), 2 deletions(-)
```
Outside the change dir: `.github/workflows/deploy.yml` (+1), `README.md` (+2), `docs/backups.md`, `docs/release-bump.md`, `ansible/inventory/host_vars/rues-cooking-hub01/vars.yml`, `ansible/playbooks/02_SERVICES/rues-cooking-hub.yml`, `ansible/roles/rues_cooking_hub/**` (17 files), `terraform/environments/homelab/hosts.auto.tfvars` (+13).

Screenshots: none.

## Review

Fresh-context reviewer (opus, round 1, diff `origin/main...flow/add-rues-cooking-hub`): **no findings** in all four categories.

- Weakened tests: none; the test-only diff (`scripts/`, `*test*`) is empty.
- Weak tests: no new `Scenario:` tests were added; the service scenarios are `manual (one-shot …)` or `manual (post-merge)` by design (D2).
- Spec mismatch: none; the role is a clean rename of `rues_arcade`, URLs, paths, IP and sizing match the spec.
- Correctness: none; handler names, variables, smoke `Host` header, nginx 16m vs app 16M and the single-line pin all hold.
- Known gap, declared in the spec (R7) and chosen by Rue as a Non-Goal: nothing guards that `sqlite_snapshot` runs before `rues_cooking_hub` in the new playbook (the sqlite fixtures hardcode the two existing hosts). Checked once by hand above.

Fixer rounds: 0. Verifier deviation worth knowing: `scripts/deploy-targets.sh` range mode needs the gitignored rendered inventory, which a fresh worktree lacks; the verifier used a throwaway fixture inventory and removed it.
