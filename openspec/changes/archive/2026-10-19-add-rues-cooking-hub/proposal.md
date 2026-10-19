## Why

Rue's Cooking Hub (own repo `Rue-Asha/Rues-Cooking-Hub`, SvelteKit adapter-node + SQLite, recipe photos stored as BLOBs) has no place to run. It needs its own LXC, configured like Rues-Arcade, serving plain HTTP on the LAN.

Appetite: one evening.

## What Changes

- **S1** `terraform/environments/homelab/hosts.auto.tfvars` gets an `lxc_hosts` entry `rues-cooking-hub01`: `ipv4 = 192.168.0.228/24`, `groups = ["rues_cooking_hub"]`, `tags = ["web","terraform"]`, 2 cores, 4096 MiB RAM, 512 MiB swap, 16 GiB disk, its own sizing comment, no `vmid`. Merging creates the LXC through the runner's plan → `infrastructure` approval → apply.
- **S2** New role `ansible/roles/rues_cooking_hub/`, cloned from `rues_arcade` with every name moved to `rues_cooking_hub`/`rues-cooking-hub`: release tarball `rues-cooking-hub-<ver>.tgz` (+ `.sha256`) from `https://github.com/Rue-Asha/Rues-Cooking-Hub/releases/download`, paths under `/opt|/var/lib|/etc/rues-cooking-hub`, database `rues-cooking-hub.db`, default version `v0.1.0`.
- **S3** The role's `env.j2` adds `BODY_SIZE_LIMIT={{ rues_cooking_hub_body_size_limit }}` (default `16M`) so photo uploads up to 15 MB reach the app.
- **S4** New playbook `ansible/playbooks/02_SERVICES/rues-cooking-hub.yml` (`hosts: rues_cooking_hub`; `common`, `nodejs`, `nginx`, `sqlite_snapshot`, `rues_cooking_hub`), picked up by the existing deploy mapping.
- **S5** New `ansible/inventory/host_vars/rues-cooking-hub01/vars.yml`: version pin `v0.1.0` on one line, smoke headers, timezone, nginx reverse proxy with `nginx_client_max_body_size: 16m`, and the `sqlite_backups` registry entry.
- **S6** `deploy.yml`'s `workflow_dispatch` playbook choice gains `rues-cooking-hub`.
- **S7** Docs: `README.md` (roles table, playbook example), the role's `README.md`, `docs/backups.md`, `docs/release-bump.md`.
- **S8** Delta specs: `release-bump` gets a per-app requirement for Rues-Cooking-Hub; `sqlite-backups` names the new app where it lists registered services and playbooks.
- **S9** A rollout runbook in the role README (pre-merge `ssh-keygen -F`, merge only after tag `v0.1.0` with its assets, `infrastructure` approval, `fetch-inventory.sh`, then `sqlite_backup.yml` `--check` and for real). It is documentation plus the post-merge checklist in `verification.md`, never a task.

## Non-Goals

- DNS name, TLS/HTTPS — Rue said no for now; consequence: plain `http://192.168.0.228` is no secure context, so no service worker/Wake Lock/clipboard in the browser.
- Websocket/SSE support in the shared nginx template — the app doesn't need it; it would touch life-manager01 and rues-arcade01.
- Extending the hardcoded hosts in `scripts/tests/sqlite-snapshot.sh` and `sqlite-backup.sh` to the third host — Rue chose to leave them; the new host stays uncovered by those two fixture tests (the `sqlite_snapshot`-before-role order of the new playbook is checked by diff review and a one-shot check recorded in `verification.md`, not by a sensor).
- Registering the repo on check01 — separate chore `flow/check01-cooking-hub`.
- Pinning a Proxmox `vmid` — Proxmox assigns it; `lxc_ctid` is read back.
- Any change to shared roles (`nginx`, `nodejs`, `common`, `sqlite_snapshot`).
- Terraform apply or playbook runs from the workstation — only via `deploy.yml` after merge; the first release's bump failure (no host_vars yet) is accepted and not repaired here.

## Done criteria

- [ ] `scripts/proof.sh --all` is green on the branch and CI on the PR is green.
- [ ] `terraform plan` output shows exactly one new LXC `rues-cooking-hub01` at `.228` and no change to existing guests. CI does not plan; the plan is the `plan` job log of the post-merge `deploy` run, read before approving `infrastructure`.
- [ ] `ansible-playbook --syntax-check ansible/playbooks/02_SERVICES/rues-cooking-hub.yml` is shown as evidence; a `--check` run against the not-yet-existing host is not possible, and the evidence says so.
- [ ] After Rue merges post-tag: `http://192.168.0.228/healthz` answers 200, the service runs `v0.1.0`, and the db path is in the nightly backup run.

The last criterion and the plan can only be checked after the merge, because only `runner01` plans and applies Terraform and `rues-cooking-hub01` does not exist before. Every `manual (post-merge …)` scenario forms the post-merge checklist the verifier carries into `verification.md`; Rue works through it with the runbook in `ansible/roles/rues_cooking_hub/README.md`. No task in `tasks.md` waits for the merge, and flow never merges this change (ship stops at the open PR; Rue merges after tag `v0.1.0`).

## Capabilities

### New Capabilities
- `rues-cooking-hub`: the `rues-cooking-hub01` guest, the `rues_cooking_hub` role, its `02_SERVICES` playbook and host_vars, the photo-upload size limits, the manual-dispatch entry, the docs and the rollout runbook.

### Modified Capabilities
- `release-bump`: adds the per-app requirement that Rues-Cooking-Hub releases bump `rues_cooking_hub_version` in `host_vars/rues-cooking-hub01/vars.yml`.
- `sqlite-backups`: the registry and the snapshot-before-service-role requirements name Rues-Cooking-Hub next to Life-Manager and Rues-Arcade.

## Impact

- New: `ansible/roles/rues_cooking_hub/`, `ansible/playbooks/02_SERVICES/rues-cooking-hub.yml`, `ansible/inventory/host_vars/rues-cooking-hub01/vars.yml`.
- Changed: `terraform/environments/homelab/hosts.auto.tfvars` (one new guest), `.github/workflows/deploy.yml` (one choice), `README.md`, `docs/backups.md`, `docs/release-bump.md`.
- Unchanged and relied on: `scripts/deploy-targets.sh` (globs `02_SERVICES/*.yml`), the `nginx`, `nodejs`, `common`, `sqlite_snapshot` roles, `scripts/checks/unique-hosts.py`.
- Live systems, on Rue's merge only: Proxmox node (new LXC), the new guest (service deploy), proxmox1's nightly backup config (after the manual `sqlite_backup.yml` re-run).
