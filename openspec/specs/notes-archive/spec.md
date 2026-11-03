# notes-archive Specification

## Purpose
TBD - created by archiving change notes-archive-deploy. Update Purpose after archive.
## Requirements
### Requirement: notes-archive01 is declared in Terraform

`terraform/environments/homelab/hosts.auto.tfvars` SHALL declare `notes-archive01` in `lxc_hosts` with the literal IPv4 `192.168.0.232/24`, `groups = ["notes_archive"]`, `tags = ["web", "terraform"]`, 2 cores, 4096 MB memory, 512 MB swap, 16 GB disk, a comment stating its sizing reason and the playbook that configures it, and no `vmid`, so Proxmox assigns the container ID. The commented-out `retropie01` block SHALL say that `.231` moved to `notes-archive01` and that retropie01 must pick a new address when revived, and SHALL no longer carry the stale `vmid = 231` line (an IP-derived ID). Applying the change SHALL create exactly one new container and change no existing guest. The generated `ansible/inventory/00-terraform.yml` SHALL NOT be edited by hand.

#### Scenario: notes-archive01 is declared with the agreed identity
- **WHEN** the `notes-archive01` entry in `hosts.auto.tfvars` is read
- **THEN** it opens on a `"notes-archive01" = {` line and has `ipv4 = "192.168.0.232/24"`, `groups = ["notes_archive"]`, `tags = ["web", "terraform"]`, `cores = 2`, `memory = 4096`, `swap = 512`, `disk_gb = 16`, a comment above it naming the sizing reason and `02_SERVICES/notes-archive.yml`, and no `vmid`
- **proof:** manual (diff review of `terraform/`; no sensor distinguishes the agreed literals from other valid values)

#### Scenario: Terraform sensors stay green with the new guest
- **WHEN** `scripts/proof.sh --all` runs with the new entry
- **THEN** `terraform fmt`, `terraform validate`, `tflint`, `checkov` and the unique-hosts sensor pass
- **proof:** unit (`scripts/proof.sh --all`: `PASS: terraform fmt`, `PASS: terraform validate`, `PASS: tflint`, `PASS: checkov`, `PASS: Regression: arcade shares IP with check container`)

#### Scenario: The address does not collide
- **WHEN** another `lxc_hosts` entry declares `192.168.0.232`
- **THEN** `scripts/proof.sh` fails with `DUPLICATE_HOST_ADDRESS`; with the entries on the branch (`.223`–`.231`) it passes, the `.231` inside the retropie01 comment is not counted because `unique-hosts.py` skips comment lines, and a duplicate hostname is impossible because `lxc_hosts` is a map keyed by hostname
- **proof:** unit (existing fixture "duplicate ipv4 without vmids" in `scripts/tests/unique-hosts.sh`; `PASS: Regression: arcade shares IP with check container` on the branch)

#### Scenario: The retropie01 note records the moved address
- **WHEN** `rg -n 'notes-archive01' terraform/environments/homelab/hosts.auto.tfvars` runs
- **THEN** besides the new entry it finds a line in the retropie01 comment block saying `.231` now belongs to `notes-archive01` and retropie01 needs a new address when it returns, `rg -n 'vmid += 231' terraform/environments/homelab/hosts.auto.tfvars` finds nothing, and `git diff main...HEAD -- terraform/` changes nothing else in that block
- **proof:** manual (one-shot command recorded in `verification.md`; comment text, no sensor reads it)

#### Scenario: The generated inventory is not edited
- **WHEN** `git diff --name-only main...HEAD -- ansible/inventory/00-terraform.yml` and `git ls-files ansible/inventory/00-terraform.yml` run on the branch
- **THEN** both print nothing (the file stays gitignored and untracked)
- **proof:** manual (one-shot commands recorded in `verification.md`)

#### Scenario: The runner plan shows exactly one new container
- **WHEN** Rue merges the PR and `runner01` runs the `plan` job of `deploy.yml`
- **THEN** the plan log lists one `create` for `module.lxc["notes-archive01"]` and no change to any other guest, before Rue approves `infrastructure`
- **proof:** manual (post-merge; only `runner01` plans against live state, CI does not plan)

#### Scenario: notes-archive01 chains to proxmox_guest
- **WHEN** after the apply Rue runs `scripts/fetch-inventory.sh` and `ansible-inventory --graph`
- **THEN** `notes-archive01` appears under `notes_archive` → `lxc_container_proxmox` → `proxmox_guest` with `ansible_host` `192.168.0.232` and an `lxc_ctid`
- **proof:** manual (post-merge; the inventory is rendered from runner state)

### Requirement: notes-archive01 host vars pin the release and register the database

`ansible/inventory/host_vars/notes-archive01/vars.yml` SHALL be the `creative-archive01` file with names moved to Notes-Archive, holding exactly one line `notes_archive_version: v0.1.0` (unquoted, no trailing comment), `notes_archive_smoke_headers` with `Host: "{{ nginx_server_name }}"`, `common_timezone: Europe/Berlin`, the nginx reverse-proxy block with backend `127.0.0.1:{{ notes_archive_port }}` and `nginx_client_max_body_size: 18m`, and a `sqlite_backups` entry with service, owner and group `notes-archive`, unit `notes-archive.service`, mode `"0640"`, `release_link: /opt/notes-archive/current`, `healthz_url: http://127.0.0.1/healthz` and `databases: [/var/lib/notes-archive/notes-archive.db]`.

#### Scenario: The pin is one plain line the bump job can edit
- **WHEN** `rg -c '^notes_archive_version: ' ansible/inventory/host_vars/notes-archive01/vars.yml` runs
- **THEN** it prints `1`, and that line is exactly `notes_archive_version: v0.1.0` (unquoted, no comment)
- **proof:** manual (one-shot command recorded in `verification.md`; `scripts/bump-pin.sh` lives in `Rue-Asha/ci` and is not run here)

#### Scenario: nginx proxies to the service port
- **WHEN** the file is read with python
- **THEN** `nginx_reverse_proxy_enabled` is `true`, `nginx_backend_host` is `127.0.0.1`, `nginx_backend_port` is `"{{ notes_archive_port }}"`, `common_timezone` is set, and `notes_archive_smoke_headers` sends `Host: "{{ nginx_server_name }}"` so the smoke check reaches the app's vhost and not nginx's default site
- **proof:** manual (one-shot python check recorded in `verification.md`; `ansible-inventory --host` cannot resolve the host before it is in the rendered inventory)

#### Scenario: The registry entry matches the role's paths
- **WHEN** the file's `sqlite_backups` is read with python
- **THEN** `databases` is `["/var/lib/notes-archive/notes-archive.db"]`, `unit` is `notes-archive.service`, `release_link` is `/opt/notes-archive/current`, and service, owner and group are `notes-archive`
- **proof:** unit ("Scenario: Notes-Archive is registered" in `scripts/tests/sqlite-snapshot.sh` covers `databases`, `unit` and `owner`); manual (one-shot python check of `release_link`, service and group recorded in `verification.md`)

#### Scenario: Host vars pass lint
- **WHEN** `scripts/proof.sh --all` runs
- **THEN** `ansible-lint` passes over the new host_vars file and the `sqlite-snapshot fixtures` sensor (triggered by `host_vars/*`) stays green
- **proof:** unit (`scripts/proof.sh --all`: `PASS: ansible-lint`, `PASS: sqlite-snapshot fixtures`)

#### Scenario: The release assets are public before the first tag
- **WHEN** runbook step 2 runs `curl -fsSIL` without a login on `https://github.com/Rue-Asha/Notes-Archive/releases/download/v0.1.0/notes-archive-0.1.0.tgz` and its `.sha256`
- **THEN** both answer 200 only if `Rue-Asha/Notes-Archive` is public; while it is private they answer 404 and every deploy fails at the fetch task, because the role downloads anonymously and adds no token auth; the role README names public visibility as a precondition, and `rg -n 'token|Authorization|url_password' ansible/roles/notes_archive/tasks/fetch.yml` finds nothing
- **proof:** manual (the `rg` is a one-shot recorded in `verification.md`; the curl is a pre-merge runbook step against GitHub, the repo's visibility is Rue's setting)

#### Scenario: Merging before the tag fails the first deploy
- **WHEN** the PR is merged while tag `v0.1.0` or its assets do not exist in `Rue-Asha/Notes-Archive`
- **THEN** the apply still creates the guest, and the fetch task fails the deploy run before `current` exists (accepted, R1)
- **proof:** manual (post-merge; expected outcome of the first deploy while the app has no release)

### Requirement: The notes_archive role deploys the pinned release

`ansible/roles/notes_archive/` SHALL be the `creative_archive` role with every name moved to `notes_archive` (variables) and `notes-archive` (user, group, service, paths, handler, unit template), and SHALL keep its behaviour: download `notes-archive-<X.Y.Z>.tgz` for `notes_archive_version` from `https://github.com/Rue-Asha/Notes-Archive/releases/download/<tag>/`, verify it against the release's `.sha256` (`<hex>  <name>.tgz`), unpack it with `--strip-components=1` into `/opt/notes-archive/releases/<ts>`, flip `/opt/notes-archive/current`, restart `notes-archive.service`, keep the database at `/var/lib/notes-archive/notes-archive.db` in a data directory owned by the service user and writable by the unit, keep the environment file at `/etc/notes-archive/env`, smoke-check `http://127.0.0.1/healthz` through nginx with the existing rollback, and prune old releases. Its default version SHALL be `v0.1.0`. The environment file SHALL set `HOST=127.0.0.1`, `PORT=3000`, `NODE_ENV=production` (kept from the clone), `DATABASE_PATH=/var/lib/notes-archive/notes-archive.db`, `PROTOCOL_HEADER=x-forwarded-proto` and `BODY_SIZE_LIMIT=17M`, and SHALL never set `NOTES_ARCHIVE_TEST` or `MOCKUP_PHOTOS_DIR`. The role SHALL add no migrate step (the app migrates on start), SHALL hold no secret and SHALL need no vault file. `tasks/main.yml` SHALL stay an import-only hub. The guest's Node.js SHALL be ≥ 22.18 for `node:sqlite`, provided by the unchanged `nodejs` role.

#### Scenario: No creative-archive name remains in the role
- **WHEN** `rg -i 'creative' ansible/roles/notes_archive` runs
- **THEN** it finds nothing, and `rg -n 'notes_archive_version: v0.1.0' ansible/roles/notes_archive/defaults/main.yml` finds the default
- **proof:** manual (one-shot commands recorded in `verification.md`)

#### Scenario: The role passes lint inside its playbook
- **WHEN** `scripts/proof.sh --all` runs
- **THEN** `ansible-lint` and `syntax-check ansible/playbooks/02_SERVICES/notes-archive.yml` pass
- **proof:** unit (`scripts/proof.sh --all`: `PASS: ansible-lint`, `PASS: syntax-check ansible/playbooks/02_SERVICES/notes-archive.yml`)

#### Scenario: The artifact URL names the Notes-Archive release
- **WHEN** the role's defaults are rendered for `notes_archive_version: v0.1.0`
- **THEN** the artifact URL is `https://github.com/Rue-Asha/Notes-Archive/releases/download/v0.1.0/notes-archive-0.1.0.tgz` and the checksum URL is the same with `.sha256` appended
- **proof:** manual (one-shot `ansible localhost -m ansible.builtin.debug -a "msg={{ notes_archive_artifact_url }}" -e @ansible/roles/notes_archive/defaults/main.yml` recorded in `verification.md`)

#### Scenario: The environment file carries exactly the agreed variables
- **WHEN** `ansible/roles/notes_archive/templates/env.j2` and `defaults/main.yml` are read
- **THEN** the template sets `HOST`, `PORT`, `NODE_ENV`, `DATABASE_PATH`, `PROTOCOL_HEADER` and `BODY_SIZE_LIMIT` and nothing else, with defaults `127.0.0.1`, `3000`, `production`, `/var/lib/notes-archive/notes-archive.db`, `x-forwarded-proto` and `17M`
- **proof:** manual (one-shot `rg` recorded in `verification.md`)

#### Scenario: Test routes and mockup photos stay off
- **WHEN** `rg -n 'NOTES_ARCHIVE_TEST|MOCKUP_PHOTOS_DIR' ansible/` runs
- **THEN** it finds nothing, so the `/__test/*` and `/__mockups` routes stay off on the guest
- **proof:** manual (one-shot command recorded in `verification.md`)

#### Scenario: The role holds no secret
- **WHEN** `fd -t f . ansible/roles/notes_archive ansible/inventory/host_vars/notes-archive01` and `rg -n 'vault|password|token' ansible/roles/notes_archive ansible/inventory/host_vars/notes-archive01` run
- **THEN** there is no `vault.yml` and no match
- **proof:** manual (one-shot commands recorded in `verification.md`)

#### Scenario: The tarball's top-level directory is stripped
- **WHEN** `fetch.yml` unpacks the release (`notes-archive-<X.Y.Z>/` holding `build/`, `migrations/`, `node_modules/`, `package.json`)
- **THEN** the unarchive task keeps `extra_opts: [--strip-components=1]`, so those land directly in `releases/<ts>/`, `migrations/` sits beside `package.json`, and the unit's `WorkingDirectory` is that package root
- **proof:** manual (diff review against `creative_archive/tasks/fetch.yml`; the live unpack is post-merge)

#### Scenario: No migrate task exists
- **WHEN** `rg -n -i 'migrat' ansible/roles/notes_archive/tasks` runs
- **THEN** it finds no task that runs migrations; the defaults' comment says the app migrates on start, and the role README says migrations must stay additive (new files only, R3)
- **proof:** manual (one-shot command and README read recorded in `verification.md`)

#### Scenario: The WAL files can be written beside the database
- **WHEN** `tasks/directories.yml` and `templates/notes-archive.service.j2` are read
- **THEN** `/var/lib/notes-archive` is owned by `notes-archive:notes-archive` and the unit runs as that user with `ReadWritePaths=/var/lib/notes-archive` (through `notes_archive_data_dir`), so SQLite can create `notes-archive.db-wal` and `-shm` next to the database under `ProtectSystem=strict`
- **proof:** manual (diff review against `creative_archive`; WAL creation is observed only on the live guest)

#### Scenario: A checksum mismatch fails before current flips
- **WHEN** the downloaded tarball does not match its `.sha256`
- **THEN** the fetch task fails the play and `current` still points at the previous release (unchanged creative-archive behaviour)
- **proof:** manual (unchanged `get_url` `checksum:` from `creative_archive`, checked by diff review; not reproducible without a tampered release)

#### Scenario: A failed smoke check rolls back
- **WHEN** `/healthz` through nginx does not answer 2xx within retries × delay after a run that swapped `current`
- **THEN** `current` points back at the previous release, the service restarts on it and the play fails (unchanged `verify.yml`, ordered before `prune.yml`)
- **proof:** manual (diff review against `creative_archive/tasks/verify.yml` and `tasks/main.yml`; not reproducible without a broken release)

#### Scenario: The nodejs role already satisfies Node 22.18
- **WHEN** `git diff --name-only main...HEAD -- ansible/roles/nodejs` runs, and after the first deploy `node --version` runs on `notes-archive01`
- **THEN** the diff is empty (`nodejs_version` stays `"22"`, NodeSource `node_22.x`) and the guest reports `v22.18.0` or later
- **proof:** manual (the diff is a one-shot command recorded in `verification.md`; the version check is post-merge on the live guest)

#### Scenario: The first deploy comes up healthy
- **WHEN** the playbook runs for a published `v0.1.0` (post-merge deploy or the manual dispatch of runbook step 7)
- **THEN** `http://192.168.0.232/healthz` answers 200, `/opt/notes-archive/current/.deployed_version` reads `v0.1.0`, and `notes-archive.service` is active
- **proof:** manual (post-merge; needs the live guest and the published `v0.1.0` release)

### Requirement: Uploads up to 16 MiB pass nginx and the app

The role default `notes_archive_body_size_limit` SHALL be `17M` and SHALL be rendered as `BODY_SIZE_LIMIT`, and `host_vars/notes-archive01/vars.yml` SHALL set `nginx_client_max_body_size: 18m`, so nginx is never stricter than the app and a 16 MiB image reaches the app. No shared role SHALL change.

#### Scenario: nginx is never stricter than the app
- **WHEN** both values are read from the role defaults and the host vars
- **THEN** `nginx_client_max_body_size` is `18m` and `notes_archive_body_size_limit` is `17M`, so a request the app accepts is never rejected with 413 by nginx first
- **proof:** manual (one-shot `rg` of both values recorded in `verification.md`)

#### Scenario: Changing the limit restarts the service
- **WHEN** `notes_archive_body_size_limit` changes and the playbook runs
- **THEN** the env file task reports changed and notifies `Restart notes-archive` (the cloned `config.yml` handler wiring)
- **proof:** manual (diff review of `tasks/config.yml` and `handlers/main.yml`; live restart is post-merge)

#### Scenario: A 16 MiB image uploads
- **WHEN** after the first healthy deploy Rue uploads an image of about 16 MiB through `http://192.168.0.232`
- **THEN** the upload succeeds; neither nginx (413) nor the app rejects it
- **proof:** manual (post-merge; needs the live service and a browser)

#### Scenario: No shared role changes
- **WHEN** `git diff --name-only main...HEAD -- ansible/roles/nginx ansible/roles/nodejs ansible/roles/common ansible/roles/sqlite_snapshot` runs
- **THEN** it lists nothing
- **proof:** manual (one-shot command recorded in `verification.md`)

### Requirement: The Notes-Archive playbook deploys through CD

`ansible/playbooks/02_SERVICES/notes-archive.yml` SHALL target `hosts: notes_archive` and apply `common`, `nodejs`, `nginx`, `sqlite_snapshot`, `notes_archive` in that order. `scripts/deploy-targets.sh` SHALL select it without a script change, from the merge diff and by name, and the `check_runner_repos` change SHALL select no playbook.

#### Scenario: The playbook applies the roles in order
- **WHEN** the playbook is read
- **THEN** it has one play with `hosts: notes_archive`, `become: true`, and roles `common`, `nodejs`, `nginx`, `sqlite_snapshot`, `notes_archive` in that order
- **proof:** unit ("Scenario: The Notes-Archive playbook runs the snapshot role before its service role" in `scripts/tests/sqlite-snapshot.sh` covers `sqlite_snapshot` before `notes_archive`); manual (one-shot python check of the full role order, `hosts` and `become` recorded in `verification.md`)

#### Scenario: The merge diff selects the new playbook
- **WHEN** `scripts/deploy-targets.sh main HEAD` runs on the branch (with a throwaway rendered inventory, removed afterwards)
- **THEN** its output is exactly `ansible/playbooks/02_SERVICES/notes-archive.yml` (the `group_vars/check_runner` change adds nothing), and `scripts/deploy-targets.sh notes-archive` prints that path
- **proof:** manual (one-shot commands recorded in `verification.md`; `deploy-targets.sh` is unchanged, so its fixtures do not run)

#### Scenario: deploy-targets.sh is unchanged
- **WHEN** `git diff --name-only main...HEAD -- scripts/` runs
- **THEN** it lists only `scripts/tests/sqlite-snapshot.sh`; `scripts/deploy-targets.sh`, `scripts/tests/deploy-targets.sh`, `scripts/checks/unique-hosts.py` and `scripts/tests/unique-hosts.sh` are not in it
- **proof:** manual (one-shot command recorded in `verification.md`)

#### Scenario: The first deploy runs the new playbook once
- **WHEN** the post-merge `deploy` job runs after the apply created `notes-archive01`
- **THEN** "Playbooks to run" lists `02_SERVICES/notes-archive.yml` exactly once and no other playbook
- **proof:** manual (post-merge; needs the live runner)

### Requirement: Notes-Archive can be redeployed by hand from the deploy workflow

`.github/workflows/deploy.yml` SHALL list `notes-archive` in the `workflow_dispatch` `playbook` choice options after `creative-archive`, and SHALL change in no other way. This dispatch SHALL be the documented way to bring up a release whose tag equals the existing pin.

#### Scenario: The dispatch list offers Notes-Archive
- **WHEN** `deploy.yml` is read
- **THEN** `inputs.playbook.options` is `all`, `life-manager`, `rues-arcade`, `rues-cooking-hub`, `creative-archive`, `notes-archive`, and `git diff main...HEAD -- .github/workflows/deploy.yml` shows only that added line
- **proof:** manual (diff review; one line)

#### Scenario: Workflow checks stay green
- **WHEN** `scripts/proof.sh --all` runs and CI runs the security baseline on the PR
- **THEN** `PASS: workflow triggers` is printed and the `security-baseline / workflow-lint` check is green
- **proof:** unit (`scripts/proof.sh --all`: `PASS: workflow triggers`); manual (CI check on the PR)

#### Scenario: A first release equal to the pin goes live by dispatch
- **WHEN** the merge happened before `v0.1.0` existed and the tag is published later
- **THEN** no bump PR deploys it (the pin already reads `v0.1.0`), and dispatching `deploy.yml` with playbook `notes-archive` runs only `02_SERVICES/notes-archive.yml` and brings the service up healthy
- **proof:** manual (post-merge; needs the live runner and the published tag)

### Requirement: Notes-Archive PRs can run on the shared check runner

`check_runner_repos` in `ansible/inventory/group_vars/check_runner/vars.yml` SHALL list `- repo: Rue-Asha/Notes-Archive` after `Rue-Asha/Creative-Archive`, and `docs/check-runner.md` SHALL name `Notes-Archive` in the repo list at the top and in the rollback bullet for app repos. Registration on `check01` SHALL be a runbook step run by Rue, never by this change.

#### Scenario: The repo list names Notes-Archive
- **WHEN** `rg -n 'Rue-Asha/Notes-Archive' ansible/inventory/group_vars/check_runner/vars.yml` and `rg -c 'Notes-Archive' docs/check-runner.md` run
- **THEN** the first finds one `- repo:` entry as the last list item, and the second prints `2` (intro list and rollback bullet)
- **proof:** manual (one-shot commands recorded in `verification.md`); unit (`scripts/proof.sh --all`: `PASS: ansible-lint` over the group_vars file)

#### Scenario: Registration without the fork-approval policy fails naming the repo
- **WHEN** Rue runs `01_BASE_CONFIGURATION/check_runner.yml` while Notes-Archive's fork-PR approval is not "all external contributors" or the `gh` login lacks admin on it
- **THEN** the play fails for `Rue-Asha/Notes-Archive` before any token is minted, naming the repo (existing check-runner behaviour); the runbook lists both preconditions
- **proof:** manual (needs GitHub; doc review of the runbook at Gate 2)

#### Scenario: The Notes-Archive runner comes online
- **WHEN** Rue runs `check_runner.yml --check` and then without `--check` after the merge
- **THEN** a new instance for Notes-Archive is online in that repo's Settings → Actions → Runners with label `homelab-check`, and the other instances are not restarted
- **proof:** manual (post-merge; needs the live runner and GitHub)

### Requirement: Notes-Archive is documented

`README.md` SHALL list the `notes_archive` role in its roles table and show its playbook command; `ansible/roles/notes_archive/README.md` SHALL describe the role like the `creative_archive` README, including `notes_archive_body_size_limit`, the env line of the on-host layout and that migrations must stay additive; `docs/backups.md` SHALL name Notes-Archive among the backed-up apps; `docs/release-bump.md` SHALL list Notes-Archive under wired-up apps with `notes_archive_version` and its host_vars path; `.claude/CLAUDE.md` SHALL carry the line `- Before changing notes-archive, read openspec/specs/notes-archive/spec.md.` under `## Specs`, written by the closer at archive.

#### Scenario: Every doc names the new service
- **WHEN** `rg -l 'notes_archive|notes-archive|Notes-Archive' README.md docs/backups.md docs/release-bump.md docs/check-runner.md ansible/roles/notes_archive/README.md` runs
- **THEN** all five files are listed, and `rg -i 'creative' ansible/roles/notes_archive/README.md` finds nothing
- **proof:** manual (one-shot command recorded in `verification.md`; prose read at Gate 2)

#### Scenario: The Specs line points at the new capability
- **WHEN** after the closer's archive commit `rg -c 'Before changing notes-archive, read openspec/specs/notes-archive/spec.md' .claude/CLAUDE.md` runs
- **THEN** it prints `1` and the file it names exists
- **proof:** manual (written by the closer at archive, after verification; checked on the archive commit)

### Requirement: The first rollout is a documented runbook, not a task

`ansible/roles/notes_archive/README.md` SHALL carry a "First rollout" section with the ten steps of `proposal.md` → "First rollout" in that order: host-key check on `runner01` for `192.168.0.232`; the visibility and tag gate (the repo MUST be public before the first tag, checked by anonymous `curl` of the `v0.1.0` assets); merge; read the `plan` job log of `deploy.yml` (one create, nothing else) and approve `infrastructure`; the deploy job runs `02_SERVICES/notes-archive.yml` once (healthy with the tag, failing at fetch without it); `scripts/fetch-inventory.sh` and `ansible-inventory --graph`; the manual dispatch once a late tag exists; `sqlite_backup.yml --check` then without `--check`, only after a healthy deploy; the next nightly run logs `notes-archive01: ok`; check-runner registration with its two preconditions. Each live step SHALL be marked ⚠, each step SHALL name the spec scenario it answers, the section SHALL name the `plan` job as the only place the terraform plan appears, and it SHALL state that the app has no auth and the guest is reachable only on `http://192.168.0.232` in the LAN and through the tailscale subnet router. The README's Requirements SHALL name a public `Rue-Asha/Notes-Archive` as a precondition and say a private repo makes every deploy fail at fetch, since no token auth is added. `tasks.md` SHALL contain none of these steps.

#### Scenario: The runbook lists the steps in order
- **WHEN** the role README's "First rollout" section is read
- **THEN** it has the ten steps above in that order, the live ones marked ⚠, each naming its spec scenario, and names the `plan` job in `deploy.yml` as the only place the terraform plan appears
- **proof:** manual (doc review at Gate 2; prose)

#### Scenario: A stale host key would block the apply
- **WHEN** `ssh-keygen -F 192.168.0.232` on `runner01` finds a key before the merge (the address was retropie01's)
- **THEN** the runbook says to remove that entry with `ssh-keygen -R 192.168.0.232` before merging, because `tf-ci.sh apply` skips the keyscan for an address it already knows
- **proof:** manual (pre-merge step on `runner01`; doc review at Gate 2)

#### Scenario: The runbook states the exposure
- **WHEN** `rg -n 'no auth|tailscale' ansible/roles/notes_archive/README.md` runs
- **THEN** it finds the statement that the app has no auth and is reachable only on the LAN IP and through the tailscale subnet router, with no DNS name and no TLS
- **proof:** manual (one-shot command recorded in `verification.md`; prose read at Gate 2)

#### Scenario: No rollout step is a task
- **WHEN** `tasks.md` is read
- **THEN** it has no task to merge, approve `infrastructure`, run `terraform plan`/`apply`, run a playbook against a real host, register the check runner, or tag a release
- **proof:** manual (plan review at Gate 1)

