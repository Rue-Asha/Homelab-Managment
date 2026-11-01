# creative-archive Specification

## Purpose
TBD - created by archiving change creative-archive-deploy. Update Purpose after archive.
## Requirements
### Requirement: creative-archive01 is declared in Terraform

`terraform/environments/homelab/hosts.auto.tfvars` SHALL declare `creative-archive01` in `lxc_hosts` with the literal IPv4 `192.168.0.229/24`, `groups = ["creative_archive"]`, `tags = ["web", "terraform"]`, 2 cores, 4096 MB memory, 512 MB swap, 16 GB disk, a comment stating its sizing reason and the playbook that configures it, and no `vmid`, so Proxmox assigns the container ID. Applying the change SHALL create exactly one new container and change no existing guest. The generated `ansible/inventory/00-terraform.yml` SHALL NOT be edited by hand.

#### Scenario: creative-archive01 is declared with the agreed identity
- **WHEN** the `creative-archive01` entry in `hosts.auto.tfvars` is read
- **THEN** it opens on a `"creative-archive01" = {` line and has `ipv4 = "192.168.0.229/24"`, `groups = ["creative_archive"]`, `tags = ["web", "terraform"]`, `cores = 2`, `memory = 4096`, `swap = 512`, `disk_gb = 16`, a comment above it naming `02_SERVICES/creative-archive.yml`, and no `vmid`
- **proof:** manual (diff review of `terraform/`; no sensor distinguishes the agreed literals from other valid values)

#### Scenario: Terraform sensors stay green with the new guest
- **WHEN** `scripts/proof.sh --all` runs with the new entry
- **THEN** `terraform fmt`, `terraform validate`, `tflint`, `checkov` and the unique-hosts sensor pass
- **proof:** unit (`scripts/proof.sh --all`: `PASS: terraform fmt`, `PASS: terraform validate`, `PASS: tflint`, `PASS: checkov`, `PASS: Regression: arcade shares IP with check container`)

#### Scenario: The address does not collide
- **WHEN** another `lxc_hosts` entry declares `192.168.0.229`
- **THEN** `scripts/proof.sh` fails with `DUPLICATE_HOST_ADDRESS`; with the entries on the branch (`.223`–`.228`, `.229`, `.230`) it passes, and a duplicate hostname is impossible because `lxc_hosts` is a map keyed by hostname
- **proof:** unit (existing fixture "duplicate ipv4 without vmids" in `scripts/tests/unique-hosts.sh`; `PASS: Regression: arcade shares IP with check container` on the branch)

#### Scenario: The generated inventory is not edited
- **WHEN** `git diff --name-only main...HEAD -- ansible/inventory/00-terraform.yml` and `git ls-files ansible/inventory/00-terraform.yml` run on the branch
- **THEN** both print nothing (the file stays gitignored and untracked)
- **proof:** manual (one-shot commands recorded in `verification.md`)

#### Scenario: The runner plan shows exactly one new container
- **WHEN** Rue merges the PR and `runner01` runs the `plan` job of `deploy.yml`
- **THEN** the plan log lists one `create` for `module.lxc["creative-archive01"]` and no change to any other guest, before Rue approves `infrastructure`
- **proof:** manual (post-merge; only `runner01` plans against live state, CI does not plan)

#### Scenario: creative-archive01 chains to proxmox_guest
- **WHEN** after the apply Rue runs `scripts/fetch-inventory.sh` and `ansible-inventory --graph`
- **THEN** `creative-archive01` appears under `creative_archive` → `lxc_container_proxmox` → `proxmox_guest` with `ansible_host` `192.168.0.229` and an `lxc_ctid`
- **proof:** manual (post-merge; the inventory is rendered from runner state)

### Requirement: creative-archive01 host vars pin the release and register the database

`ansible/inventory/host_vars/creative-archive01/vars.yml` SHALL be the `rues-cooking-hub01` file with names moved to the Creative Archive, holding exactly one line `creative_archive_version: v0.1.0` (unquoted, no trailing comment), `creative_archive_smoke_headers` with `Host: "{{ nginx_server_name }}"`, `common_timezone: Europe/Berlin`, the nginx reverse-proxy block with backend `127.0.0.1:{{ creative_archive_port }}` and `nginx_client_max_body_size: 18m`, and a `sqlite_backups` entry with service, owner and group `creative-archive`, unit `creative-archive.service`, mode `"0640"`, `release_link: /opt/creative-archive/current`, `healthz_url: http://127.0.0.1/healthz` and `databases: [/var/lib/creative-archive/creative-archive.db]`.

#### Scenario: The pin is one plain line the bump job can edit
- **WHEN** `rg -c '^creative_archive_version: ' ansible/inventory/host_vars/creative-archive01/vars.yml` runs
- **THEN** it prints `1`, and that line is exactly `creative_archive_version: v0.1.0` (unquoted, no comment)
- **proof:** manual (one-shot command recorded in `verification.md`; `scripts/bump-pin.sh` lives in `Rue-Asha/ci` and is not run here)

#### Scenario: nginx proxies to the service port
- **WHEN** the file is read with python
- **THEN** `nginx_reverse_proxy_enabled` is `true`, `nginx_backend_host` is `127.0.0.1`, `nginx_backend_port` is `"{{ creative_archive_port }}"`, `common_timezone` is set, and `creative_archive_smoke_headers` sends `Host: "{{ nginx_server_name }}"` so the smoke check reaches the app's vhost and not nginx's default site
- **proof:** manual (one-shot python check recorded in `verification.md`; `ansible-inventory --host` cannot resolve the host before it is in the rendered inventory)

#### Scenario: The registry entry matches the role's paths
- **WHEN** the file's `sqlite_backups` is read with python
- **THEN** `databases` is `["/var/lib/creative-archive/creative-archive.db"]`, `unit` is `creative-archive.service`, `release_link` is `/opt/creative-archive/current`, and service, owner and group are `creative-archive`
- **proof:** unit ("Scenario: Creative-Archive is registered" in `scripts/tests/sqlite-snapshot.sh` covers `databases`, `unit` and `owner`); manual (one-shot python check of `release_link`, service and group recorded in `verification.md`)

#### Scenario: Host vars pass lint
- **WHEN** `scripts/proof.sh --all` runs
- **THEN** `ansible-lint` passes over the new host_vars file and the `sqlite-snapshot fixtures` sensor (triggered by `host_vars/*`) stays green
- **proof:** unit (`scripts/proof.sh --all`: `PASS: ansible-lint`, `PASS: sqlite-snapshot fixtures`)

#### Scenario: Merging before the tag fails the first deploy
- **WHEN** the PR is merged while tag `v0.1.0` or its assets do not exist in `Rue-Asha/Creative-Archive`
- **THEN** the guest is created but the fetch task fails the deploy run before `current` exists; the runbook says to merge only after the tag (accepted, R1)
- **proof:** manual (procedure; not reproduced)

### Requirement: The creative_archive role deploys the pinned release

`ansible/roles/creative_archive/` SHALL be the `rues_cooking_hub` role with every name moved to `creative_archive` (variables) and `creative-archive` (user, group, service, paths, handler, unit template), and SHALL keep its behaviour: download `creative-archive-<X.Y.Z>.tgz` for `creative_archive_version` from `https://github.com/Rue-Asha/Creative-Archive/releases/download/<tag>/`, verify it against the release's `.sha256`, unpack it with `--strip-components=1` into `/opt/creative-archive/releases/<ts>`, flip `/opt/creative-archive/current`, restart `creative-archive.service`, keep the database at `/var/lib/creative-archive/creative-archive.db` and the environment file at `/etc/creative-archive/env`, smoke-check `http://127.0.0.1/healthz` through nginx with the existing rollback, and prune old releases. Its default version SHALL be `v0.1.0`. The role SHALL add no migrate step (the app migrates on start), SHALL hold no secret and SHALL need no vault file. `tasks/main.yml` SHALL stay an import-only hub.

#### Scenario: No cooking-hub name remains in the role
- **WHEN** `rg -i 'cooking|rues' ansible/roles/creative_archive` runs
- **THEN** it finds nothing, and `rg -n 'creative_archive_version: v0.1.0' ansible/roles/creative_archive/defaults/main.yml` finds the default
- **proof:** manual (one-shot commands recorded in `verification.md`)

#### Scenario: The role passes lint inside its playbook
- **WHEN** `scripts/proof.sh --all` runs
- **THEN** `ansible-lint` and `syntax-check ansible/playbooks/02_SERVICES/creative-archive.yml` pass
- **proof:** unit (`scripts/proof.sh --all`: `PASS: ansible-lint`, `PASS: syntax-check ansible/playbooks/02_SERVICES/creative-archive.yml`)

#### Scenario: The artifact URL names the Creative-Archive release
- **WHEN** the role's defaults are rendered for `creative_archive_version: v0.1.0`
- **THEN** the artifact URL is `https://github.com/Rue-Asha/Creative-Archive/releases/download/v0.1.0/creative-archive-0.1.0.tgz` and the checksum URL is the same with `.sha256` appended
- **proof:** manual (one-shot `ansible localhost -m ansible.builtin.debug -a "msg={{ creative_archive_artifact_url }}" -e @ansible/roles/creative_archive/defaults/main.yml` recorded in `verification.md`)

#### Scenario: The environment file carries exactly the agreed variables
- **WHEN** `ansible/roles/creative_archive/templates/env.j2` and `defaults/main.yml` are read
- **THEN** the template sets `HOST`, `PORT`, `NODE_ENV`, `DATABASE_PATH`, `PROTOCOL_HEADER` and `BODY_SIZE_LIMIT` and nothing else, with defaults `127.0.0.1`, `3000`, `production`, `/var/lib/creative-archive/creative-archive.db`, `x-forwarded-proto` and `17M`
- **proof:** manual (one-shot `rg` recorded in `verification.md`)

#### Scenario: The test switch is never set
- **WHEN** `rg -n 'CREATIVE_ARCHIVE_TEST' ansible/` runs
- **THEN** it finds nothing, so the `/__test/*` routes and the provider fakes stay off on the guest
- **proof:** manual (one-shot command recorded in `verification.md`)

#### Scenario: The role holds no secret
- **WHEN** `fd -t f . ansible/roles/creative_archive ansible/inventory/host_vars/creative-archive01` and `rg -n 'vault|password|token' ansible/roles/creative_archive ansible/inventory/host_vars/creative-archive01` run
- **THEN** there is no `vault.yml` and no match
- **proof:** manual (one-shot commands recorded in `verification.md`)

#### Scenario: The tarball's top-level directory is stripped
- **WHEN** `fetch.yml` unpacks the release (`creative-archive-<X.Y.Z>/` holding `build/`, `migrations/`, `node_modules/`, `package.json`)
- **THEN** the unarchive task keeps `extra_opts: [--strip-components=1]`, so those land directly in `releases/<ts>/` and the unit's `WorkingDirectory` is the package root the app reads `migrations/` from
- **proof:** manual (diff review against `rues_cooking_hub/tasks/fetch.yml`; the live unpack is post-merge)

#### Scenario: A checksum mismatch fails before current flips
- **WHEN** the downloaded tarball does not match its `.sha256`
- **THEN** the fetch task fails the play and `current` still points at the previous release (unchanged cooking-hub behaviour)
- **proof:** manual (unchanged `get_url` `checksum:` from `rues_cooking_hub`, checked by diff review; not reproducible without a tampered release)

#### Scenario: A failed smoke check rolls back
- **WHEN** `/healthz` through nginx does not answer 2xx within retries × delay after a run that swapped `current`
- **THEN** `current` points back at the previous release, the service restarts on it and the play fails (unchanged `verify.yml`, ordered before `prune.yml`)
- **proof:** manual (diff review against `rues_cooking_hub/tasks/verify.yml` and `tasks/main.yml`; not reproducible without a broken release)

#### Scenario: The first deploy comes up healthy
- **WHEN** the post-merge deploy runs the playbook for `v0.1.0`
- **THEN** `http://192.168.0.229/healthz` answers 200, `/opt/creative-archive/current/.deployed_version` reads `v0.1.0`, and `creative-archive.service` is active
- **proof:** manual (post-merge; needs the live guest and the published `v0.1.0` release)

### Requirement: Uploads up to 16 MiB pass nginx and the app

The role default `creative_archive_body_size_limit` SHALL be `17M` and SHALL be rendered as `BODY_SIZE_LIMIT`, and `host_vars/creative-archive01/vars.yml` SHALL set `nginx_client_max_body_size: 18m`, so nginx is never stricter than the app and a 16 MiB photo reaches the app. No shared role SHALL change.

#### Scenario: nginx is never stricter than the app
- **WHEN** both values are read from the role defaults and the host vars
- **THEN** `nginx_client_max_body_size` is `18m` and `creative_archive_body_size_limit` is `17M`, so a request the app accepts is never rejected with 413 by nginx first
- **proof:** manual (one-shot `rg` of both values recorded in `verification.md`)

#### Scenario: Changing the limit restarts the service
- **WHEN** `creative_archive_body_size_limit` changes and the playbook runs
- **THEN** the env file task reports changed and notifies `Restart creative-archive` (the cloned `config.yml` handler wiring)
- **proof:** manual (diff review of `tasks/config.yml` and `handlers/main.yml`; live restart is post-merge)

#### Scenario: A 16 MiB photo uploads
- **WHEN** after the first deploy Rue uploads a photo of about 16 MiB through `http://192.168.0.229`
- **THEN** the upload succeeds; neither nginx (413) nor the app rejects it
- **proof:** manual (post-merge; needs the live service and a browser)

#### Scenario: No shared role changes
- **WHEN** `git diff --name-only main...HEAD -- ansible/roles/nginx ansible/roles/nodejs ansible/roles/common ansible/roles/sqlite_snapshot` runs
- **THEN** it lists nothing
- **proof:** manual (one-shot command recorded in `verification.md`)

### Requirement: The Creative Archive playbook deploys through CD

`ansible/playbooks/02_SERVICES/creative-archive.yml` SHALL target `hosts: creative_archive` and apply `common`, `nodejs`, `nginx`, `sqlite_snapshot`, `creative_archive` in that order. `scripts/deploy-targets.sh` SHALL select it without a script change, from the merge diff and by name.

#### Scenario: The playbook applies the roles in order
- **WHEN** the playbook is read
- **THEN** it has one play with `hosts: creative_archive`, `become: true`, and roles `common`, `nodejs`, `nginx`, `sqlite_snapshot`, `creative_archive` in that order
- **proof:** unit ("Scenario: The Creative-Archive playbook runs the snapshot role before its service role" in `scripts/tests/sqlite-snapshot.sh` covers `sqlite_snapshot` before `creative_archive`); manual (one-shot python check of the full role order, `hosts` and `become` recorded in `verification.md`)

#### Scenario: The merge diff selects the new playbook
- **WHEN** `scripts/deploy-targets.sh main HEAD` runs on the branch
- **THEN** its output contains `ansible/playbooks/02_SERVICES/creative-archive.yml` and no other `02_SERVICES` playbook, and `scripts/deploy-targets.sh creative-archive` prints that path
- **proof:** manual (one-shot commands recorded in `verification.md`; `deploy-targets.sh` is unchanged, so its fixtures do not run)

#### Scenario: deploy-targets.sh is unchanged
- **WHEN** `git diff --name-only main...HEAD -- scripts/` runs
- **THEN** it lists only `scripts/tests/sqlite-snapshot.sh` (S6); `scripts/deploy-targets.sh` and `scripts/tests/deploy-targets.sh` are not in it
- **proof:** manual (one-shot command recorded in `verification.md`)

#### Scenario: The first deploy runs the new playbook once
- **WHEN** the post-merge `deploy` job runs after the apply created `creative-archive01`
- **THEN** "Playbooks to run" lists `02_SERVICES/creative-archive.yml` exactly once and no other playbook, and the job is green
- **proof:** manual (post-merge; needs the live runner)

### Requirement: The Creative Archive can be redeployed by hand from the deploy workflow

`.github/workflows/deploy.yml` SHALL list `creative-archive` in the `workflow_dispatch` `playbook` choice options after `rues-cooking-hub`, and SHALL change in no other way.

#### Scenario: The dispatch list offers the Creative Archive
- **WHEN** `deploy.yml` is read
- **THEN** `inputs.playbook.options` is `all`, `life-manager`, `rues-arcade`, `rues-cooking-hub`, `creative-archive`, and `git diff main...HEAD -- .github/workflows/deploy.yml` shows only that added line
- **proof:** manual (diff review; one line)

#### Scenario: Workflow checks stay green
- **WHEN** `scripts/proof.sh --all` runs and CI runs the security baseline on the PR
- **THEN** `PASS: workflow triggers` is printed and the `security-baseline / workflow-lint` check is green
- **proof:** unit (`scripts/proof.sh --all`: `PASS: workflow triggers`); manual (CI check on the PR)

### Requirement: The Creative Archive is documented

`README.md` SHALL list the `creative_archive` role in its roles table and show its playbook command; `ansible/roles/creative_archive/README.md` SHALL describe the role like the `rues_cooking_hub` README, including `creative_archive_body_size_limit` and the env line of the on-host layout; `docs/backups.md` SHALL name Creative-Archive among the backed-up apps; `docs/release-bump.md` SHALL list Creative-Archive under wired-up apps with `creative_archive_version` and its host_vars path; `.claude/CLAUDE.md` SHALL carry the line `- Before changing creative-archive, read openspec/specs/creative-archive/spec.md.` under `## Specs`.

#### Scenario: Every doc names the new service
- **WHEN** `rg -l 'creative_archive|creative-archive|Creative-Archive' README.md docs/backups.md docs/release-bump.md ansible/roles/creative_archive/README.md .claude/CLAUDE.md` runs
- **THEN** all five files are listed, and `rg -i 'cooking' ansible/roles/creative_archive/README.md` finds nothing
- **proof:** manual (one-shot command recorded in `verification.md`; prose read at Gate 2)

#### Scenario: The Specs line points at the new capability
- **WHEN** `rg -c 'Before changing creative-archive, read openspec/specs/creative-archive/spec.md' .claude/CLAUDE.md` runs
- **THEN** it prints `1`; the file it names exists once the change is archived
- **proof:** manual (one-shot command recorded in `verification.md`)

### Requirement: The first rollout is a documented runbook, not a task

`ansible/roles/creative_archive/README.md` SHALL carry a "First rollout" runbook, in this order: on `runner01`, `ssh-keygen -F 192.168.0.229` finds nothing (else remove the stale key first); tag `v0.1.0` exists in `Rue-Asha/Creative-Archive` with `creative-archive-0.1.0.tgz` and `.sha256`; merge the PR; read the `plan` job log of `deploy.yml` (one create, nothing else) and approve `infrastructure`; the deploy job runs `02_SERVICES/creative-archive.yml` once and the smoke check passes; from the workstation `scripts/fetch-inventory.sh` and `ansible-inventory --graph`; `ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml --check` and then without `--check`; next morning the nightly run logs `creative-archive01: ok`. Each live step SHALL be marked ⚠, and the runbook SHALL note that the app's first-release bump job fails because the host_vars file was not on `main` yet (accepted). `tasks.md` SHALL contain none of these steps.

#### Scenario: The runbook lists the steps in order
- **WHEN** the role README's "First rollout" section is read
- **THEN** it has the steps above in that order, the live ones marked ⚠, names the `plan` job in `deploy.yml` as the only place the terraform plan appears, and notes the accepted first-bump failure
- **proof:** manual (doc review at Gate 2; prose)

#### Scenario: A stale host key would block the apply
- **WHEN** `ssh-keygen -F 192.168.0.229` on `runner01` finds a key before the merge
- **THEN** the runbook says to remove that stale entry before merging, because `tf-ci.sh apply` skips the keyscan for an address it already knows
- **proof:** manual (pre-merge step on `runner01`; doc review at Gate 2)

#### Scenario: No rollout step is a task
- **WHEN** `tasks.md` is read
- **THEN** it has no task to merge, approve `infrastructure`, run `terraform plan`/`apply`, run a playbook against a real host, or tag `v0.1.0`
- **proof:** manual (plan review at Gate 1)

