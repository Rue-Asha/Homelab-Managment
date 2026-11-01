# Scope: creative-archive-deploy

Triage: tweak + live — new guest cloned from the cooking-hub pattern; Terraform and the playbook run in CI after merge. Appetite: one evening.

## Problem
Rue's Creative Archive hub (repo `Rue-Asha/Creative-Archive`) has no guest to run on. Its release workflow already bumps `creative_archive_version` in `host_vars/creative-archive01/vars.yml` and the check runner already watches the repo, but neither the guest nor that file exists, so the bump fails and nothing can be deployed.

## Flows
- Provision: merge → CI plan → `infrastructure` approval → apply creates `creative-archive01` → playbook `creative-archive.yml` deploys the pinned release.
- Release: tag in Creative-Archive → `bump-pin` rewrites `creative_archive_version` in this repo → deploy.

## In scope
- **S1** `lxc_hosts` in `terraform/environments/homelab/hosts.auto.tfvars` gets `creative-archive01`: ipv4 `192.168.0.229/24`, groups `["creative_archive"]`, tags `["web","terraform"]`, 2 cores, 4096 MB memory, 512 MB swap, 16 GB disk, no pinned vmid.
  - edges: .229 free (checked against used IPs .223–.228, .230; .231 reserved for retropie01) → no collision; generated inventory `00-terraform.yml` is never edited.
- **S2** `ansible/inventory/host_vars/creative-archive01/vars.yml` exists with exactly one line `creative_archive_version: v0.1.0` (unquoted, no trailing comment, matches `^creative_archive_version: `), the nginx reverse proxy to `127.0.0.1:{{ creative_archive_port }}` with `nginx_client_max_body_size: 18m`, `common_timezone`, and the `sqlite_backups:` block (service `creative-archive`, unit `creative-archive.service`, database `/var/lib/creative-archive/creative-archive.db`).
  - edges: the pin `v0.1.0` has no release tag yet → the playbook fails at download until the tag exists; the PR is merged only after the tag (accepted, see Decisions); bump-pin spec requires the single-line format.
- **S3** Role `ansible/roles/creative_archive` copied from `rues_cooking_hub`: releases URL `https://github.com/Rue-Asha/Creative-Archive/releases/download`, artifact `creative-archive-<version-without-v>.tgz` with sha256 check, `/opt/creative-archive/releases/<ts>` + `current` symlink, data in `/var/lib/creative-archive`, systemd unit, env file with `HOST=127.0.0.1`, `PORT=3000`, `NODE_ENV=production`, `DATABASE_PATH=/var/lib/creative-archive/creative-archive.db`, `PROTOCOL_HEADER=x-forwarded-proto`, `BODY_SIZE_LIMIT=17M`; `CREATIVE_ARCHIVE_TEST` is never set; smoke check `http://127.0.0.1/healthz` with rollback.
  - edges: migrations run on app start, nothing extra in the role; no secrets, no vault file.
- **S4** Playbook `ansible/playbooks/02_SERVICES/creative-archive.yml` for group `creative_archive` with roles `common`, `nodejs`, `nginx`, `sqlite_snapshot`, `creative_archive` in that order, and `creative-archive` is added to the `workflow_dispatch` playbook choices in `.github/workflows/deploy.yml`.
  - edges: `scripts/deploy-targets.sh` maps the diff automatically → no edit there.
- **S5** Docs and specs say the same: new capability spec `creative-archive` (delta), a Creative-Archive requirement in `release-bump` and `sqlite-backups`, rows in `README.md` (roles table, run example), `docs/backups.md`, `docs/release-bump.md` (wired-up apps), and a `## Specs` line in `.claude/CLAUDE.md`.
  - edges: post-merge rollout steps go in the docs and in verification.md as a manual checklist, never as a tasks.md unit.

- **S6** `scripts/tests/sqlite-snapshot.sh` (its `want` dict and playbook tuple are hardcoded to life-manager/rues-arcade) also covers `rues-cooking-hub01` and `creative-archive01`, so the registry entry and snapshot-before-role order are checked by `proof`. Added at Gate 1 (Rue accepted planner addition a).
  - edges: the test must stay green for the two existing hosts; red first for the new hosts before the role/playbook/host_vars exist.
- **S7** The existing "One registry entry per service host" requirement in `sqlite-backups` becomes a MODIFIED requirement that names Creative-Archive in its body, instead of only an ADDED one. Added at Gate 1 (Rue accepted planner addition b).
  - edges: none (spec wording only).

## Non-goals
- Docker/OCI image — the repo's delivery model is a tarball plus systemd per LXC.
- Reverse-proxy-by-name, Pi-hole local DNS record for the hub — nothing in the repo does that for other hubs, nginx answers on the guest IP.
- Auth, TLS or secrets for the hub — the app is keyless and single-user.
- Changes to the check runner — `Rue-Asha/Creative-Archive` is already in `check_runner_repos` (PR #58).
- Changes to the Creative-Archive repo or its release workflow — already wired.
- Egress rules for Deezer, AniList, Open Library and URL preview — no firewall exists that blocks them.
- Applying Terraform or running the playbook by hand — CI does it after merge and the `infrastructure` approval.

## Codebase touchpoints
- `terraform/environments/homelab/hosts.auto.tfvars` — new `lxc_hosts` entry (explorer: cooking-hub guest end to end)
- `ansible/inventory/host_vars/creative-archive01/vars.yml` — new (explorer: auto bump)
- `ansible/roles/creative_archive/` — new, copy of `rues_cooking_hub` (explorer)
- `ansible/playbooks/02_SERVICES/creative-archive.yml` — new (explorer)
- `.github/workflows/deploy.yml` — playbook choice list (explorer)
- `README.md`, `docs/backups.md`, `docs/release-bump.md`, `.claude/CLAUDE.md`, `openspec/specs/{release-bump,sqlite-backups}/spec.md` (explorer)

## Risks
- R1 The first apply creates the guest but the playbook fails if `v0.1.0` isn't released → accepted: merge the PR after the Creative-Archive tag (Rue's choice).
- R2 BODY_SIZE_LIMIT 17M vs nginx 18m mismatch would reject 16 MiB uploads → resolved: nginx 18m, app 17M, both written down in the spec.

## Decisions
- Sizing like the cooking hub (2 cores, 4096 MB, 16 GB) — same load: sharp plus WebP BLOBs in SQLite. Rue chose this.
- Pin starts at `v0.1.0`, PR is merged after the tag exists — the release workflow's first bump then keeps working. Rue chose this.
- Hostname `creative-archive01` and the variable name `creative_archive_version` — the Creative-Archive `release.yml` already uses them.
- Ship policy `pr` (repo `## Harness`) and `live`: the PR is opened, never merged by flow.

## Done when
- `scripts/proof.sh --all` is green.
- `terraform fmt -check` and `terraform validate` pass; `ansible-playbook --check` / syntax-check for `creative-archive.yml` passes.
- The PR is open and its CI is green; the PR description names where the terraform plan appears after merge (the plan job in `deploy.yml`).
- Rue can merge once `v0.1.0` is tagged and then approve the `infrastructure` step.

## Split off
none
