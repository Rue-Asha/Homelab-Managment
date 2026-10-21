# rues-cooking-hub Specification

## Purpose
TBD - created by archiving change add-rues-cooking-hub. Update Purpose after archive.
## Requirements
### Requirement: rues-cooking-hub01 is declared in Terraform

`terraform/environments/homelab/hosts.auto.tfvars` SHALL declare `rues-cooking-hub01` in `lxc_hosts` with the literal IPv4 `192.168.0.228/24`, `groups = ["rues_cooking_hub"]`, `tags = ["web", "terraform"]`, 2 cores, 4096 MiB RAM, 512 MiB swap, 16 GiB disk, a comment stating its sizing reason and the playbook that configures it, and no `vmid`, so Proxmox assigns the container ID. Applying the change SHALL create exactly one new container and change no existing guest.

#### Scenario: rues-cooking-hub01 is declared with the agreed identity
- **WHEN** the `rues-cooking-hub01` entry in `hosts.auto.tfvars` is read
- **THEN** it opens on a `"rues-cooking-hub01" = {` line and has `ipv4 = "192.168.0.228/24"`, `groups = ["rues_cooking_hub"]`, `tags = ["web", "terraform"]`, `cores = 2`, `memory = 4096`, `swap = 512`, `disk_gb = 16`, a comment above it, and no `vmid`
- **proof:** manual (diff review of `terraform/`; no sensor distinguishes the agreed literals from other valid values)

#### Scenario: Terraform sensors stay green with the new guest
- **WHEN** `scripts/proof.sh --all` runs with the new entry
- **THEN** `terraform fmt`, `terraform validate`, `tflint`, `checkov` and the unique-hosts sensor pass
- **proof:** unit (`scripts/proof.sh --all`: `PASS: terraform fmt`, `PASS: terraform validate`, `PASS: tflint`, `PASS: checkov`, `PASS: Regression: arcade shares IP with check container`)

#### Scenario: An address collision fails the proof
- **WHEN** another `lxc_hosts` entry declares `192.168.0.228`
- **THEN** `scripts/proof.sh` fails with `DUPLICATE_HOST_ADDRESS`; a duplicate hostname is impossible because `lxc_hosts` is a map keyed by hostname
- **proof:** unit (existing fixture "duplicate ipv4 without vmids" in `scripts/tests/unique-hosts.sh`)

#### Scenario: The runner plan shows exactly one new container
- **WHEN** Rue merges the PR and `runner01` runs the `plan` job
- **THEN** the plan log lists one `create` for `module.lxc["rues-cooking-hub01"]` and no change to any other guest, before Rue approves `infrastructure`
- **proof:** manual (post-merge; only `runner01` plans against live state, CI does not plan)

#### Scenario: rues-cooking-hub01 chains to proxmox_guest
- **WHEN** after the apply Rue runs `scripts/fetch-inventory.sh` and `ansible-inventory --graph`
- **THEN** `rues-cooking-hub01` appears under `rues_cooking_hub` → `lxc_container_proxmox` → `proxmox_guest` with `ansible_host` `192.168.0.228` and an `lxc_ctid`
- **proof:** manual (post-merge; the inventory is rendered from runner state)

### Requirement: The rues_cooking_hub role deploys the pinned release

`ansible/roles/rues_cooking_hub/` SHALL be the `rues_arcade` role with every name moved to `rues_cooking_hub` (variables) and `rues-cooking-hub` (user, group, service, paths, handler, unit template), and SHALL keep its behaviour: download `rues-cooking-hub-<X.Y.Z>.tgz` for `rues_cooking_hub_version` from `https://github.com/Rue-Asha/Rues-Cooking-Hub/releases/download/<tag>/`, verify it against the release's `.sha256`, unpack it with `--strip-components=1` into `/opt/rues-cooking-hub/releases/<ts>`, flip `/opt/rues-cooking-hub/current`, restart `rues-cooking-hub.service`, keep the database at `/var/lib/rues-cooking-hub/rues-cooking-hub.db` and the environment file at `/etc/rues-cooking-hub/env`, smoke-check `/healthz` through nginx with the existing rollback, and prune old releases. Its default version SHALL be `v0.1.0`. `tasks/main.yml` SHALL stay an import-only hub.

#### Scenario: No arcade name remains in the role
- **WHEN** `rg -i 'arcade' ansible/roles/rues_cooking_hub` runs
- **THEN** it finds nothing, and `rg -n 'rues_cooking_hub_version: v0.1.0' ansible/roles/rues_cooking_hub/defaults/main.yml` finds the default
- **proof:** manual (one-shot command recorded in `verification.md`; no fixture by Rue's choice)

#### Scenario: The role passes lint inside its playbook
- **WHEN** `scripts/proof.sh --all` runs
- **THEN** `ansible-lint` and `syntax-check ansible/playbooks/02_SERVICES/rues-cooking-hub.yml` pass
- **proof:** unit (`scripts/proof.sh --all`: `PASS: ansible-lint`, `PASS: syntax-check ansible/playbooks/02_SERVICES/rues-cooking-hub.yml`)

#### Scenario: The artifact URL names the Cooking Hub release
- **WHEN** the role's defaults are rendered for `rues_cooking_hub_version: v0.1.0`
- **THEN** the artifact URL is `https://github.com/Rue-Asha/Rues-Cooking-Hub/releases/download/v0.1.0/rues-cooking-hub-0.1.0.tgz` and the checksum URL is the same with `.sha256` appended
- **proof:** manual (one-shot `ansible localhost -m ansible.builtin.debug -a "msg={{ rues_cooking_hub_artifact_url }}" -e @ansible/roles/rues_cooking_hub/defaults/main.yml` recorded in `verification.md`)

#### Scenario: The tarball's top-level directory is stripped
- **WHEN** `fetch.yml` unpacks the release
- **THEN** the unarchive task keeps `extra_opts: [--strip-components=1]`, so `build/` and `node_modules/` land directly in `releases/<ts>/`
- **proof:** manual (diff review against `rues_arcade/tasks/fetch.yml`; the live unpack is post-merge)

#### Scenario: A checksum mismatch fails before current flips
- **WHEN** the downloaded tarball does not match its `.sha256`
- **THEN** the fetch task fails the play and `current` still points at the previous release (unchanged arcade behaviour)
- **proof:** manual (unchanged `get_url` `checksum:` from `rues_arcade`, checked by diff review; not reproducible without a tampered release)

#### Scenario: The first deploy comes up healthy
- **WHEN** the post-merge deploy runs the playbook for `v0.1.0`
- **THEN** `http://192.168.0.228/healthz` answers 200, `/opt/rues-cooking-hub/current/.deployed_version` reads `v0.1.0`, and `rues-cooking-hub.service` is active
- **proof:** manual (post-merge; needs the live guest and the published `v0.1.0` release)

### Requirement: Photo uploads up to 15 MB pass nginx and the app

The role SHALL render `BODY_SIZE_LIMIT={{ rues_cooking_hub_body_size_limit }}` into the service environment file next to `PROTOCOL_HEADER=x-forwarded-proto`, with the role default `rues_cooking_hub_body_size_limit: 16M`, and `host_vars/rues-cooking-hub01/vars.yml` SHALL set `nginx_client_max_body_size: 16m`, so nginx is never stricter than the app. No shared role SHALL change.

#### Scenario: The environment file carries the body size limit
- **WHEN** `ansible/roles/rues_cooking_hub/templates/env.j2` and `defaults/main.yml` are read
- **THEN** the template has the line `BODY_SIZE_LIMIT={{ rues_cooking_hub_body_size_limit }}` after `PROTOCOL_HEADER={{ rues_cooking_hub_protocol_header }}` and the default is `16M`
- **proof:** manual (one-shot `rg` recorded in `verification.md`; no fixture by Rue's choice)

#### Scenario: nginx does not answer 413 before the app decides
- **WHEN** the host's resolved vars are read
- **THEN** `nginx_client_max_body_size` is `16m`, equal to the app's `16M` (both 16 MiB), so a request the app accepts is never rejected by nginx first
- **proof:** manual (one-shot `rg` of both values recorded in `verification.md`; `ansible-inventory --host` cannot resolve them before the host is in the rendered inventory)

#### Scenario: Changing the limit restarts the service
- **WHEN** `rues_cooking_hub_body_size_limit` changes and the playbook runs
- **THEN** the env file task reports changed and notifies `Restart rues-cooking-hub` (the cloned `config.yml` handler wiring)
- **proof:** manual (diff review of `tasks/config.yml` and `handlers/main.yml`; live restart is post-merge)

#### Scenario: A 15 MB photo uploads
- **WHEN** after the first deploy Rue uploads a photo of about 15 MB through `http://192.168.0.228`
- **THEN** the upload succeeds; neither nginx (413) nor the app rejects it
- **proof:** manual (post-merge; needs the live service and a browser)

#### Scenario: No shared role changes
- **WHEN** `git diff --name-only main...HEAD` runs on the branch
- **THEN** it lists nothing under `ansible/roles/nginx/`, `ansible/roles/nodejs/`, `ansible/roles/common/` or `ansible/roles/sqlite_snapshot/`
- **proof:** manual (one-shot command recorded in `verification.md`)

### Requirement: The Cooking Hub playbook deploys through CD

`ansible/playbooks/02_SERVICES/rues-cooking-hub.yml` SHALL target `hosts: rues_cooking_hub` and apply `common`, `nodejs`, `nginx`, `sqlite_snapshot`, `rues_cooking_hub` in that order. `scripts/deploy-targets.sh` SHALL select it without a script change: from the merge diff, from `--created rues-cooking-hub01`, and from a later change under the role or `host_vars/rues-cooking-hub01/`.

#### Scenario: The playbook applies the roles in order
- **WHEN** the playbook is read
- **THEN** it has one play with `hosts: rues_cooking_hub`, `become: true`, and roles `common`, `nodejs`, `nginx`, `sqlite_snapshot`, `rues_cooking_hub` in that order, with `sqlite_snapshot` before `rues_cooking_hub`
- **proof:** manual (one-shot python check of the role order recorded in `verification.md`; `scripts/tests/sqlite-snapshot.sh` checks only the two existing playbooks, by Rue's choice)

#### Scenario: The merge diff selects the new playbook
- **WHEN** `scripts/deploy-targets.sh main HEAD` runs on the branch
- **THEN** its output contains `ansible/playbooks/02_SERVICES/rues-cooking-hub.yml` and no other `02_SERVICES` playbook, and `scripts/deploy-targets.sh rues-cooking-hub` prints that path
- **proof:** manual (one-shot commands recorded in `verification.md`; `deploy-targets.sh` is unchanged, so its fixtures do not run)

#### Scenario: deploy-targets.sh is unchanged
- **WHEN** `git diff --name-only main...HEAD -- scripts/` runs
- **THEN** it lists nothing
- **proof:** manual (one-shot command recorded in `verification.md`)

#### Scenario: The first deploy runs the new playbook once
- **WHEN** the post-merge `deploy` job runs after the apply created `rues-cooking-hub01`
- **THEN** "Playbooks to run" lists `02_SERVICES/rues-cooking-hub.yml` exactly once and no other playbook, and the job is green
- **proof:** manual (post-merge; needs the live runner)

### Requirement: rues-cooking-hub01 host vars pin the release and register the database

`ansible/inventory/host_vars/rues-cooking-hub01/vars.yml` SHALL be the rues-arcade01 file with names moved to the Cooking Hub, holding exactly one line `rues_cooking_hub_version: v0.1.0`, `rues_cooking_hub_smoke_headers` with `Host: "{{ nginx_server_name }}"`, `common_timezone: Europe/Berlin`, the nginx reverse-proxy block with backend `127.0.0.1:{{ rues_cooking_hub_port }}` and `nginx_client_max_body_size: 16m`, and a `sqlite_backups` entry with service, unit, owner and group `rues-cooking-hub`, mode `"0640"`, `release_link: /opt/rues-cooking-hub/current`, `healthz_url: http://127.0.0.1/healthz` and `databases: [/var/lib/rues-cooking-hub/rues-cooking-hub.db]`.

#### Scenario: The pin is one plain line the bump job can edit
- **WHEN** `rg -c '^rues_cooking_hub_version: ' ansible/inventory/host_vars/rues-cooking-hub01/vars.yml` runs
- **THEN** it prints `1`, and that line is exactly `rues_cooking_hub_version: v0.1.0` (unquoted, no comment)
- **proof:** manual (one-shot command recorded in `verification.md`)

#### Scenario: The registry entry matches the role's paths
- **WHEN** the file's `sqlite_backups` is read with python
- **THEN** `databases` is `["/var/lib/rues-cooking-hub/rues-cooking-hub.db"]` (ends in `.db`), `unit` is `rues-cooking-hub.service`, `release_link` is `/opt/rues-cooking-hub/current`, and service, owner and group are `rues-cooking-hub`
- **proof:** manual (one-shot python check recorded in `verification.md`; the role itself also rejects a non-`.db` path at run time)

#### Scenario: Host vars pass lint
- **WHEN** `scripts/proof.sh --all` runs
- **THEN** `ansible-lint` passes over the new host_vars file
- **proof:** unit (`scripts/proof.sh --all`: `PASS: ansible-lint`)

### Requirement: The Cooking Hub can be redeployed by hand from the deploy workflow

`.github/workflows/deploy.yml` SHALL list `rues-cooking-hub` in the `workflow_dispatch` `playbook` choice options after `rues-arcade`, and SHALL change in no other way.

#### Scenario: The dispatch list offers the Cooking Hub
- **WHEN** `deploy.yml` is read
- **THEN** `inputs.playbook.options` is `all`, `life-manager`, `rues-arcade`, `rues-cooking-hub`, and `git diff main...HEAD -- .github/workflows/deploy.yml` shows only that added line
- **proof:** manual (diff review; one line)

#### Scenario: Workflow checks stay green
- **WHEN** `scripts/proof.sh --all` runs and CI runs the security baseline on the PR
- **THEN** `PASS: workflow triggers` is printed and the `security-baseline / workflow-lint` (actionlint) check is green
- **proof:** unit (`scripts/proof.sh --all`: `PASS: workflow triggers`); manual (CI check on the PR)

### Requirement: The Cooking Hub is documented

`README.md` SHALL list the `rues_cooking_hub` role in its roles table and show its playbook command; `ansible/roles/rues_cooking_hub/README.md` SHALL describe the role like the `rues_arcade` README, including `rues_cooking_hub_body_size_limit` and the `BODY_SIZE_LIMIT` line in the on-host layout; `docs/backups.md` SHALL name Rues-Cooking-Hub among the backed-up apps; `docs/release-bump.md` SHALL list per app which variable in which host_vars file its bump edits, including Rues-Cooking-Hub.

#### Scenario: Every doc names the new service
- **WHEN** `rg -l 'rues_cooking_hub|rues-cooking-hub|Rues-Cooking-Hub|Rues Cooking Hub' README.md docs/backups.md docs/release-bump.md ansible/roles/rues_cooking_hub/README.md` runs
- **THEN** all four files are listed, and the role README has no `arcade` left (`rg -i arcade` finds nothing)
- **proof:** manual (one-shot command recorded in `verification.md`; prose read at Gate 2)

### Requirement: The first rollout is a documented runbook, not a task

`ansible/roles/rues_cooking_hub/README.md` SHALL carry a "First rollout" runbook, in this order: on `runner01`, `ssh-keygen -F 192.168.0.228` finds nothing (else remove the stale key first); tag `v0.1.0` exists in the app repo with `rues-cooking-hub-0.1.0.tgz` and `.sha256`; merge the PR; read the plan (one create, nothing else) and approve `infrastructure`; the deploy job runs `02_SERVICES/rues-cooking-hub.yml` once and the smoke check passes; from the workstation run `scripts/fetch-inventory.sh`, then `ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml --check` and then without `--check`. Each live step SHALL be marked ⚠, and the runbook SHALL note that the app's first-release bump job fails because the host_vars file was not on `main` yet (accepted).

#### Scenario: The runbook lists the steps in order
- **WHEN** the role README's "First rollout" section is read
- **THEN** it has the steps above in that order, the live ones marked ⚠, and the accepted first-bump failure
- **proof:** manual (doc review at Gate 2; prose)

#### Scenario: A stale host key would block the apply
- **WHEN** `ssh-keygen -F 192.168.0.228` on `runner01` finds a key before the merge
- **THEN** the runbook says to remove that stale entry before merging, because `tf-ci.sh apply` skips the keyscan for an address it already knows
- **proof:** manual (pre-merge step on `runner01`; doc review at Gate 2)

#### Scenario: Merging before the tag fails the first deploy
- **WHEN** the PR is merged while tag `v0.1.0` or its assets do not exist
- **THEN** the fetch task fails the deploy run before `current` exists; the runbook says to merge only after the tag (ship stops at the open PR)
- **proof:** manual (procedure; not reproduced)

#### Scenario: The database joins the nightly backup
- **WHEN** after the first deploy Rue runs `scripts/fetch-inventory.sh` and `00_OPERATIONAL/sqlite_backup.yml` from the workstation
- **THEN** the next nightly run on proxmox1 logs `rues-cooking-hub01: ok` and `/var/backups/homelab/rues-cooking-hub01/daily/` holds a `rues-cooking-hub-<stamp>.db` with its `.meta`
- **proof:** manual (post-merge; needs proxmox1 and the live guest)

