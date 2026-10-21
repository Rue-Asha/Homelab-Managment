# Scope: add-rues-cooking-hub

Triage: feature · live — new LXC guest + role + playbook, merge applies Terraform and deploys. Appetite: one evening.

Source plan: `~/Repos/Rues-Cooking-Hub/openspec/changes/build-cooking-hub/split-homelab.md` (names fixed there, `release.yml` of the app repo already uses them), research in `research-infra.md`, runbook step 7 in `~/Repos/Rues-Cooking-Hub/docs/release.md`.

## Problem
Rue's Cooking Hub (own repo `Rue-Asha/Rues-Cooking-Hub`, SvelteKit adapter-node + SQLite, recipe photos stored as BLOBs) has no place to run. It needs its own LXC, configured like Rues-Arcade, serving plain HTTP on the LAN.

## Flows
- Deploy: merge to `main` → `deploy.yml` plan → `infrastructure` approval → apply (creates LXC) → `02_SERVICES/rues-cooking-hub.yml` fetches the `v0.1.0` tarball, verifies sha256, switches `current`, smoke check through nginx.
- Photo upload: browser → nginx (`client_max_body_size 16m`) → app (`BODY_SIZE_LIMIT=16M`), up to 15 MB per photo.
- Backup: nightly sqlite backup covers `/var/lib/rues-cooking-hub/rues-cooking-hub.db` once `00_OPERATIONAL/sqlite_backup.yml` has been re-run by hand after the first deploy.
- Later release: the app repo's bump job opens a PR changing `rues_cooking_hub_version` in the host_vars file.

## In scope
- **S1** `terraform/environments/homelab/hosts.auto.tfvars` gets an `lxc_hosts` entry `rues-cooking-hub01`: `ipv4 = 192.168.0.228/24`, `groups = ["rues_cooking_hub"]`, `tags = ["web","terraform"]`, cores 2, memory 4096, swap 512, disk_gb 16, own sizing comment, no `vmid`.
  - edges: `scripts/checks/unique-hosts.py` must stay green (no duplicate IP; entry opens on a `"name" = {` line); `terraform fmt -check`, `validate`, `tflint`, `checkov` stay green.
- **S2** Role `ansible/roles/rues_cooking_hub/` cloned from `rues_arcade` (all `rues_arcade_`/`rues-arcade` → `rues_cooking_hub`/`rues-cooking-hub`): releases URL `https://github.com/Rue-Asha/Rues-Cooking-Hub/releases/download`, artifact `rues-cooking-hub-<ver>.tgz` (+ `.sha256`), paths `/opt|/var/lib|/etc/rues-cooking-hub`, db `rues-cooking-hub.db`, handler and service template renamed, README and meta adapted.
  - edges: tarball has one top-level dir (`--strip-components=1` stays); sha256 mismatch fails the play before `current` flips (unchanged arcade behaviour); default version is `v0.1.0`.
- **S3** `env.j2` adds `BODY_SIZE_LIMIT={{ rues_cooking_hub_body_size_limit }}`, default `16M` in role defaults, next to `PROTOCOL_HEADER=x-forwarded-proto`.
  - edges: changing the value restarts the service (config.yml handler, unchanged).
- **S4** Playbook `ansible/playbooks/02_SERVICES/rues-cooking-hub.yml`, `hosts: rues_cooking_hub`, roles in order `common`, `nodejs` (Node 22), `nginx`, `sqlite_snapshot`, `rues_cooking_hub`.
  - edges: `sqlite_snapshot` before the service role (enforced by `scripts/tests/sqlite-snapshot.sh`); `scripts/deploy-targets.sh` maps a change under the role/host_vars to this playbook (it globs `02_SERVICES/*.yml`, expected no script change, verified by a fixture-free check or existing tests).
- **S5** `ansible/inventory/host_vars/rues-cooking-hub01/vars.yml` copied from rues-arcade01: `rues_cooking_hub_version: v0.1.0`, `rues_cooking_hub_smoke_headers`, `common_timezone`, nginx reverse-proxy block (backend `127.0.0.1:{{ rues_cooking_hub_port }}`), `nginx_client_max_body_size: 16m`, `sqlite_backups` (service/unit/owner/group `rues-cooking-hub`, mode `0640`, `release_link /opt/rues-cooking-hub/current`, `healthz_url http://127.0.0.1/healthz`, databases `[/var/lib/rues-cooking-hub/rues-cooking-hub.db]`).
  - edges: nginx limit ≥ app limit (16m vs 16M) so nginx doesn't answer 413 first; db path ends in `.db`; the pin line is the one the bump job edits, so it stays a single `rues_cooking_hub_version: vX.Y.Z` line.
- **S6** `.github/workflows/deploy.yml` `workflow_dispatch` `playbook` choice list gains `rues-cooking-hub`.
  - edges: actionlint / workflow checks stay green.
- **S7** Docs: `README.md` roles table row and playbook example, role `README.md`, `docs/backups.md` (names the new app), `docs/release-bump.md` (per-app lines).
- **S8** Specs: `release-bump` gets a per-app requirement for Rues-Cooking-Hub (like Rues-Arcade's, naming `rues-cooking-hub01`, `ansible/inventory/host_vars/rues-cooking-hub01/vars.yml`, `rues_cooking_hub_version`); `sqlite-backups` names the new app wherever it lists registered services/playbooks.
  - edges: delta specs only, synced on archive; every scenario carries a proof line.
- **S9** Rollout runbook (docs, not a task unit): pre-merge on runner01 `ssh-keygen -F 192.168.0.228` must find nothing; merge only after tag `v0.1.0` exists with `rues-cooking-hub-0.1.0.tgz` + `.sha256`; approve `infrastructure`; after the first deploy run `scripts/fetch-inventory.sh`, then `sqlite_backup.yml --check` and for real from the workstation. Lives in the docs and as the manual post-merge checklist in `verification.md`.

## Non-goals
- DNS name, TLS/HTTPS — Rue said no for now; consequence: plain `http://192.168.0.228` is no secure context, so no service worker/Wake Lock/clipboard in the browser.
- Websocket/SSE support in the shared nginx template — the app doesn't need it; it would touch life-manager01 and rues-arcade01.
- Extending the hardcoded hosts in `scripts/tests/sqlite-snapshot.sh` and `sqlite-backup.sh` to the third host — Rue chose to leave them; the new host stays uncovered by those two fixture tests (the `sqlite_snapshot`-before-role order is still enforced for the playbook by the check where it globs, otherwise unchecked).
- Registering the repo on check01 — separate chore `flow/check01-cooking-hub`.
- Pinning a Proxmox `vmid` — Proxmox assigns it; `lxc_ctid` is read back.
- Any change to shared roles (`nginx`, `nodejs`, `common`, `sqlite_snapshot`).
- Terraform apply or playbook runs from the workstation — only via `deploy.yml` after merge; the first release's bump failure (no host_vars yet) is accepted and not repaired here.

## Codebase touchpoints
- `terraform/environments/homelab/hosts.auto.tfvars` — new entry (explorer: free IP, lxc_hosts shape)
- `ansible/roles/rues_cooking_hub/**` — clone of `ansible/roles/rues_arcade/**` (explorer: role walk)
- `ansible/playbooks/02_SERVICES/rues-cooking-hub.yml`, `ansible/inventory/host_vars/rues-cooking-hub01/vars.yml` — new
- `.github/workflows/deploy.yml:33-34` — choice list
- `README.md:18,75`, `docs/backups.md:3`, `docs/release-bump.md` — docs
- `openspec/specs/release-bump/spec.md:150-160`, `openspec/specs/sqlite-backups/spec.md:10-12,50-51` — spec lists
- `ansible/roles/nginx/defaults/main.yml` — `nginx_client_max_body_size` already exists (default 10m), no role change

## Risks
- R1 Hostname/group mismatch (`rues-cooking-hub01` vs `rues_cooking_hub`) breaks the playbook's `hosts:` → resolved: names fixed in split-homelab.md, `groups` becomes the Ansible group.
- R2 Router DHCP range may include .228 → accepted: Rue checks the router; `ssh-keygen -F` pre-merge covers runner01's known_hosts only.
- R3 App tarball layout, `/healthz` and Node ≥ 22.18 unverified from this repo → accepted: contract is in the app's `research-infra.md`; the smoke check rolls back a bad first release.
- R4 Merge before tag `v0.1.0` makes the first deploy fail on the fetch → accepted and guarded by procedure: ship stops at the open PR, Rue merges after the tag.
- R5 First release's bump job fails (host_vars absent) → accepted (R4 in the app plan).

## Decisions
- IP `192.168.0.228` — Rue's choice; .228/.229 appear nowhere in the repo, .231 reserved by retropie01.
- Size 2 cores / 4096 MB / 16 GB disk / swap 512 — Rue's choice, above the plan's 1–2 GB guess for Sharp downscaling and photo BLOBs.
- No tests extension for the hardcoded sqlite fixture scripts — Rue's choice.
- `BODY_SIZE_LIMIT` as a role default variable (`rues_cooking_hub_body_size_limit: 16M`) rather than hardcoded in `env.j2` — smallest design that keeps the repo's `<role>_<name>` convention; a hardcoded value would have been one line shorter.
- Ship is `pr` (live); Rue merges after tag v0.1.0. Flow never merges this change.

## Done when
- `scripts/proof.sh --all` is green on the branch and CI on the PR is green.
- `terraform plan` output (from CI, or the PR's plan) shows exactly one new LXC `rues-cooking-hub01` at .228 and no change to existing guests.
- A `--check` syntax/dry run of the playbook is shown as evidence (`ansible-playbook --syntax-check`; `--check` against the not-yet-existing host is not possible and is said so).
- After Rue merges post-tag: `http://192.168.0.228/healthz` answers 200, the service runs `v0.1.0`, and the db path is in the nightly backup run.

## Split off
- none
