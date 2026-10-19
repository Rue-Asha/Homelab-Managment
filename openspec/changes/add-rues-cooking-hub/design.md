## Context

Third app-per-LXC web service after Life-Manager and Rues-Arcade. The app repo (`Rue-Asha/Rues-Cooking-Hub`) already fixes the names this repo must use: its `release.yml` publishes `rues-cooking-hub-<X.Y.Z>.tgz` + `.sha256` (one top-level directory) and its `bump` job targets `rues_cooking_hub_version` in `ansible/inventory/host_vars/rues-cooking-hub01/vars.yml`. Everything here is a rename of the Rues-Arcade wiring plus the upload size limits and the sizing. Problem, flows, S-items, non-goals and Done criteria are in `scope.md` and `proposal.md`; this file records how.

## Goals / Non-Goals

**Goals:** a merge (after tag `v0.1.0`) creates `rues-cooking-hub01`, deploys `v0.1.0` behind nginx and passes the smoke check; 15 MB photos upload; the database is backed up like the other two apps; later tags bump themselves.

**Non-Goals:** see `proposal.md` → Non-Goals (DNS/TLS, websocket/SSE in nginx, extending the hardcoded sqlite fixtures, check01 registration, a pinned vmid, shared-role changes, workstation applies/playbook runs).

## Decisions

Carried over from scope.md as decided at Gate 0:

- **IP `192.168.0.228`** — Rue's choice; .228/.229 appear nowhere in the repo, .231 reserved by retropie01.
- **Size 2 cores / 4096 MB / 16 GB disk / swap 512** — Rue's choice, above the plan's 1–2 GB guess for Sharp downscaling and photo BLOBs.
- **No tests extension for the hardcoded sqlite fixture scripts** — Rue's choice.
- **`BODY_SIZE_LIMIT` as a role default variable** (`rues_cooking_hub_body_size_limit: 16M`) rather than hardcoded in `env.j2` — smallest design that keeps the repo's `<role>_<name>` convention; a hardcoded value would have been one line shorter.
- **Ship is `pr` (live); Rue merges after tag v0.1.0.** Flow never merges this change.

Made while planning:

- **D1 One new capability, `rues-cooking-hub`, plus two deltas.** The generic behaviour this change relies on (diff → playbook mapping, created guest → playbook, smoke check + rollback, keyed `lxc_hosts`, unique addresses) is already specified in `continuous-deployment` and `terraform-provisioning` and does not change, so neither gets a delta; adding the third service's names there would turn generic requirements into a service list. The service-specific facts (identity and sizing, release source, upload limits, playbook role order, pin line, dispatch entry, docs, runbook) have no home in an existing capability, and the repo's precedent for a guest + role + playbook is a per-service capability (`tailscale-subnet-router`, `pihole-dns`). `release-bump` and `sqlite-backups` already name each app, so they get the S8 deltas: an ADDED per-app requirement in `release-bump` (like Rues-Arcade's) and MODIFIED blocks in `sqlite-backups` that add one scenario each for the new app while keeping the existing ones verbatim.
- **D2 Proof without new fixtures.** Rue declined extending the hardcoded sqlite fixtures, and scope.md adds no new test script, so service-specific scenarios are proven by the existing sensors (`terraform fmt/validate/tflint/checkov`, `unique-hosts`, `ansible-lint`, `--syntax-check`, `workflow triggers`) or by named one-shot commands the builder runs and the verifier repeats into `verification.md` (`manual (one-shot …)`). Live behaviour is post-merge. A small `scripts/tests/rues-cooking-hub.sh` would turn the one-shots into a sensor; it is listed as an addition, not planned.
- **D3 Deploy mapping needs no script change.** On the merge push the diff contains the new playbook file itself, so `scripts/deploy-targets.sh` selects `02_SERVICES/rues-cooking-hub.yml` even before the host is in the rendered inventory, and `--created rues-cooking-hub01` selects it again (printed once). Later bumps change only `host_vars/rues-cooking-hub01/`, which maps through `--list-hosts` against the runner-rendered inventory, where Terraform places the host under `rues_cooking_hub` → `lxc_container_proxmox` → `proxmox_guest`. Proven locally with `scripts/deploy-targets.sh main HEAD` and `scripts/deploy-targets.sh rues-cooking-hub` on the branch.
- **D4 Role README owns the runbook (S9) and is written by the docs unit.** The README is "setup next to the code" (workspace documentation contract), so the first-rollout runbook goes there instead of a new `docs/` page. The service unit creates every other role file; the docs unit creates `ansible/roles/rues_cooking_hub/README.md`, so the two units touch disjoint files.
- **D5 Upload limits.** nginx `16m` and adapter-node `16M` are both 16 MiB; a 15 MB photo plus multipart framing stays under both, and nginx is never stricter than the app, so the app (not nginx) decides. `nginx_client_max_body_size` is an existing nginx role variable (default `10m`), set only in this host's vars.
- **D6 Unit cut: three parallel units.** U1 Terraform entry (only unit that needs the terraform cache dance), U2 service code (role + playbook + host_vars + `deploy.yml`; playbook and role in one unit so its hook passes), U3 docs incl. role README/runbook. File sets are disjoint and no unit needs another's output to pass `proof.sh --staged`: the docs only name the Contracts below. S8 is delivered by this plan's delta specs (synced on archive), so no unit carries it.

## Contracts

Shared by U1–U3 (parallel; all must use these literals):

| Name | Value | Used by |
|---|---|---|
| Host / group / IP | `rues-cooking-hub01`, group `rues_cooking_hub`, `192.168.0.228/24` | U1 tfvars, U2 playbook + host_vars dir, U3 docs |
| Terraform entry | `"rues-cooking-hub01" = { ipv4 = "192.168.0.228/24", groups = ["rues_cooking_hub"], tags = ["web", "terraform"], cores = 2, memory = 4096, swap = 512, disk_gb = 16 }`, no `vmid`, own comment above it, placed after `rues-arcade01` | U1 |
| Role | `ansible/roles/rues_cooking_hub/`, every `rues_arcade_`/`rues-arcade`/`Rues-Arcade`/`Rues Arcade` → `rues_cooking_hub_`/`rues-cooking-hub`/`Rues-Cooking-Hub`/`Rues Cooking Hub`; handler `Restart rues-cooking-hub`; template `rues-cooking-hub.service.j2` | U2, U3 role README |
| Release source | `rues_cooking_hub_releases_url: https://github.com/Rue-Asha/Rues-Cooking-Hub/releases/download`, artifact `rues-cooking-hub-<X.Y.Z>.tgz` + `.sha256`, `--strip-components=1`, default `rues_cooking_hub_version: v0.1.0` | U2, U3 |
| On-host paths | `/opt/rues-cooking-hub` (`releases/`, `current`), `/var/lib/rues-cooking-hub/rues-cooking-hub.db`, `/etc/rues-cooking-hub/env`; user/group/service `rues-cooking-hub`; port `3000` on `127.0.0.1` | U2, U3 |
| Body size | role default `rues_cooking_hub_body_size_limit: 16M` → `env.j2` line `BODY_SIZE_LIMIT={{ rues_cooking_hub_body_size_limit }}` after `PROTOCOL_HEADER=…`; host var `nginx_client_max_body_size: 16m` | U2, U3 |
| Playbook | `ansible/playbooks/02_SERVICES/rues-cooking-hub.yml`, `hosts: rues_cooking_hub`, roles `common`, `nodejs`, `nginx`, `sqlite_snapshot`, `rues_cooking_hub` in that order (Node 22 is the `nodejs` default) | U2, U3 |
| Host vars | `ansible/inventory/host_vars/rues-cooking-hub01/vars.yml`: exactly one line `rues_cooking_hub_version: v0.1.0`; `rues_cooking_hub_smoke_headers: {Host: "{{ nginx_server_name }}"}`; `common_timezone: Europe/Berlin`; nginx block as rues-arcade01 with `nginx_backend_port: "{{ rues_cooking_hub_port }}"` and `nginx_client_max_body_size: 16m`; `sqlite_backups` {service/unit `rues-cooking-hub`/`rues-cooking-hub.service`, owner/group `rues-cooking-hub`, mode `"0640"`, `release_link: /opt/rues-cooking-hub/current`, `healthz_url: http://127.0.0.1/healthz`, `databases: [/var/lib/rues-cooking-hub/rues-cooking-hub.db]`} | U2, U3 |
| Dispatch choice | `rues-cooking-hub` appended to `deploy.yml` `inputs.playbook.options` after `rues-arcade` | U2, U3 |
| Bump wiring | app `rues-cooking-hub`, variable `rues_cooking_hub_version`, host_vars path above | U3 docs |

## Risks / Trade-offs

- **R1 Hostname/group mismatch breaks `hosts:`** → resolved: names fixed in the Contracts and in the app repo; `groups` becomes the Ansible group.
- **R2 Router DHCP range may include .228** → accepted: Rue checks the router; `ssh-keygen -F` pre-merge covers runner01's known_hosts only.
- **R3 App tarball layout, `/healthz` and Node ≥ 22.18 unverified from this repo** → accepted: contract is in the app's `research-infra.md`; the smoke check rolls back a bad first release (with no previous release the play just fails).
- **R4 Merge before tag `v0.1.0` makes the first deploy fail on the fetch** → accepted and guarded by procedure: ship stops at the open PR, Rue merges after the tag.
- **R5 First release's bump job fails (host_vars absent)** → accepted.
- **R6 Live behaviour is provable only after merge** → Gate 2 evidence is the sensors, syntax-check and the one-shot checks; the `manual (post-merge …)` scenarios form the post-merge checklist in `verification.md`, worked through by Rue with the runbook. `tasks.md` holds no post-merge task.
- **R7 The order `sqlite_snapshot` before `rues_cooking_hub` is not guarded by a sensor** (consequence of the fixture non-goal) → a later edit could reorder it unnoticed; mitigated only by review.
- **R8 Until `sqlite_backup.yml` is re-run, the nightly job does not cover the new database** → the runbook makes it the last rollout step; pre-deploy snapshots on the guest still happen from the first deploy on.
