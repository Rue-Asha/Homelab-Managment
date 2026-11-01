## Why

Rue's Creative Archive hub (repo `Rue-Asha/Creative-Archive`) has no guest to run on. Its release workflow already bumps `creative_archive_version` in `host_vars/creative-archive01/vars.yml` and the check runner already watches the repo, but neither the guest nor that file exists, so the bump fails and nothing can be deployed.

Appetite: one evening.

## What Changes

- **S1** `terraform/environments/homelab/hosts.auto.tfvars` gets an `lxc_hosts` entry `creative-archive01`: `ipv4 = "192.168.0.229/24"`, `groups = ["creative_archive"]`, `tags = ["web", "terraform"]`, 2 cores, 4096 MB memory, 512 MB swap, 16 GB disk, no pinned `vmid`. `.229` is free (used: `.223`–`.228`, `.230`; `.231` reserved for retropie01). The generated inventory `ansible/inventory/00-terraform.yml` is never edited. Merging creates the LXC through the runner's plan → `infrastructure` approval → apply.
- **S2** New `ansible/inventory/host_vars/creative-archive01/vars.yml`: exactly one line `creative_archive_version: v0.1.0` (unquoted, no trailing comment, matches `^creative_archive_version: `), the nginx reverse proxy to `127.0.0.1:{{ creative_archive_port }}` with `nginx_client_max_body_size: 18m`, `common_timezone`, and the `sqlite_backups:` block (service `creative-archive`, unit `creative-archive.service`, database `/var/lib/creative-archive/creative-archive.db`).
- **S3** New role `ansible/roles/creative_archive`, copied from `rues_cooking_hub`: releases URL `https://github.com/Rue-Asha/Creative-Archive/releases/download`, artifact `creative-archive-<version-without-v>.tgz` with sha256 check, `/opt/creative-archive/releases/<ts>` + `current` symlink, data in `/var/lib/creative-archive`, systemd unit, env file with `HOST=127.0.0.1`, `PORT=3000`, `NODE_ENV=production`, `DATABASE_PATH=/var/lib/creative-archive/creative-archive.db`, `PROTOCOL_HEADER=x-forwarded-proto`, `BODY_SIZE_LIMIT=17M`; `CREATIVE_ARCHIVE_TEST` is never set; smoke check `http://127.0.0.1/healthz` with rollback. Migrations run on app start, nothing extra in the role; no secrets, no vault file.
- **S4** New playbook `ansible/playbooks/02_SERVICES/creative-archive.yml` for group `creative_archive` with roles `common`, `nodejs`, `nginx`, `sqlite_snapshot`, `creative_archive` in that order; `creative-archive` is added to the `workflow_dispatch` playbook choices in `.github/workflows/deploy.yml`. `scripts/deploy-targets.sh` maps the diff automatically, so it is not edited.
- **S5** Docs and specs say the same: new capability spec `creative-archive`, a Creative-Archive requirement in `release-bump` and `sqlite-backups`, rows in `README.md` (roles table, run example), `docs/backups.md`, `docs/release-bump.md` (wired-up apps), a `## Specs` line in `.claude/CLAUDE.md`, and the role's `README.md` with the "First rollout" runbook below. Post-merge rollout steps live in the docs and in `verification.md` as a manual checklist, never as a `tasks.md` unit.
- **S6** `scripts/tests/sqlite-snapshot.sh` (its `want` dict and playbook tuple are hardcoded to life-manager/rues-arcade) also covers `rues-cooking-hub01` and `creative-archive01`, so the registry entry and snapshot-before-role order are checked by `proof`. The two existing hosts stay green; the Creative-Archive checks are red first, before the host_vars file and playbook exist. Added at Gate 1.
- **S7** The existing "One registry entry per service host" requirement in `sqlite-backups` becomes a MODIFIED requirement that names Creative-Archive in its body, instead of only an ADDED one. Spec wording only. Added at Gate 1.

## Non-Goals

- Docker/OCI image — the repo's delivery model is a tarball plus systemd per LXC.
- Reverse-proxy-by-name, Pi-hole local DNS record for the hub — nothing in the repo does that for other hubs, nginx answers on the guest IP.
- Auth, TLS or secrets for the hub — the app is keyless and single-user.
- Changes to the check runner — `Rue-Asha/Creative-Archive` is already in `check_runner_repos` (PR #58).
- Changes to the Creative-Archive repo or its release workflow — already wired.
- Egress rules for Deezer, AniList, Open Library and URL preview — no firewall exists that blocks them.
- Applying Terraform or running the playbook by hand — CI does it after merge and the `infrastructure` approval.

## Decisions

- Sizing like the cooking hub (2 cores, 4096 MB, 16 GB) — same load: sharp plus WebP BLOBs in SQLite. Rue chose this.
- Pin starts at `v0.1.0`, PR is merged after the tag exists — the release workflow's first bump then keeps working. Rue chose this.
- Hostname `creative-archive01` and the variable name `creative_archive_version` — the Creative-Archive `release.yml` already uses them.
- Ship policy `pr` (repo `## Harness`) and `live`: the PR is opened, never merged by flow.

## Risks

- R1 The first apply creates the guest but the playbook fails if `v0.1.0` isn't released → accepted: merge the PR after the Creative-Archive tag (Rue's choice).
- R2 `BODY_SIZE_LIMIT` 17M vs nginx 18m mismatch would reject 16 MiB uploads → resolved: nginx `18m`, app `17M`, both written down in the spec.

## Done criteria

- [ ] `scripts/proof.sh --all` is green.
- [ ] `terraform fmt -check` and `terraform validate` pass; `ansible-playbook --syntax-check` for `creative-archive.yml` passes. A `--check` run needs the guest, which only exists after the post-merge apply; the evidence says so instead of faking it.
- [ ] The PR is open and its CI is green; the PR description names where the terraform plan appears after merge (the `plan` job in `deploy.yml`).
- [ ] Rue can merge once `v0.1.0` is tagged and then approve the `infrastructure` step.

## Where the plan is visible

CI (`ci.yml`) runs `proof.sh --all` on the PR, which covers `terraform fmt -check`, `validate`, `tflint` and `checkov`, but never `terraform plan`: the workstation and CI hold no state. The only plan is the `plan` job of the `deploy` workflow on `runner01`, after the merge, and it waits for the `infrastructure` approval before `apply`. Pre-merge dry-run evidence is therefore `terraform fmt -check` + `terraform validate` and `ansible-playbook --syntax-check`; nobody runs `terraform plan`/`apply` or a playbook against real hosts before the merge.

## First rollout (runbook, after the PR is green)

Not tasks. Rue does these; the verifier copies them into `verification.md` as the post-merge checklist, together with every `manual (post-merge …)` scenario. The same steps live in `ansible/roles/creative_archive/README.md` → "First rollout". ⚠ marks steps that change live systems.

1. On `runner01`, `ssh-keygen -F 192.168.0.229` finds nothing; else remove the stale entry first (`scripts/tf-ci.sh apply` skips the keyscan for an address it already knows).
2. Tag `v0.1.0` exists in `Rue-Asha/Creative-Archive` with `creative-archive-0.1.0.tgz` and its `.sha256`.
3. ⚠ Merge the PR.
4. Read the `plan` job log: exactly one create, `module.lxc["creative-archive01"]`, nothing else. Then ⚠ approve `infrastructure` (apply creates the container).
5. The `deploy` job lists `02_SERVICES/creative-archive.yml` once and its smoke check passes; `http://192.168.0.229/healthz` answers 200.
6. From the workstation: `scripts/fetch-inventory.sh`, then `ansible-inventory --graph` shows `creative-archive01` under `creative_archive` → `lxc_container_proxmox` → `proxmox_guest` with an `lxc_ctid`.
7. `ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml --check`, then ⚠ without `--check`, so the nightly node job collects the new database.
8. Next morning the nightly run on proxmox1 logs `creative-archive01: ok`.

The app's `v0.1.0` bump job fails on the missing host_vars file because it ran before this change was on `main`; that is accepted and needs nothing. Later tags bump by themselves.

## Capabilities

### New Capabilities
- `creative-archive`: the `creative-archive01` guest, the `creative_archive` role, its `02_SERVICES` playbook and host_vars, the upload size limits, the manual-dispatch entry, the docs and the rollout runbook.

### Modified Capabilities
- `release-bump`: adds the per-app requirement that Creative-Archive releases bump `creative_archive_version` in `host_vars/creative-archive01/vars.yml`.
- `sqlite-backups`: MODIFIED "One registry entry per service host drives every backup step" (names Creative-Archive; the Rues-Cooking-Hub and Creative-Archive registry scenarios become unit proof via `scripts/tests/sqlite-snapshot.sh`) and MODIFIED "Service playbooks snapshot the database before the service role runs" (same for the playbook order, a consequence of S6); ADDED "The Creative-Archive database joins the nightly backup".

## Impact

- New: `ansible/roles/creative_archive/`, `ansible/playbooks/02_SERVICES/creative-archive.yml`, `ansible/inventory/host_vars/creative-archive01/vars.yml`.
- Changed: `terraform/environments/homelab/hosts.auto.tfvars` (one new guest), `.github/workflows/deploy.yml` (one choice), `scripts/tests/sqlite-snapshot.sh` (four new checks), `README.md`, `docs/backups.md`, `docs/release-bump.md`, `.claude/CLAUDE.md` (one `## Specs` line).
- Unchanged and relied on: `scripts/deploy-targets.sh` and its fixtures (globs `02_SERVICES/*.yml`), `scripts/proof.sh` (already runs `sqlite-snapshot fixtures` when `scripts/tests/sqlite-snapshot.sh`, `02_SERVICES/*` or `host_vars/*` change), the `nginx`, `nodejs`, `common`, `sqlite_snapshot` roles, `scripts/checks/unique-hosts.py`.
- Live systems, on Rue's merge only: Proxmox node (new LXC), the new guest (service deploy), proxmox1's nightly backup config (after the manual `sqlite_backup.yml` run).
