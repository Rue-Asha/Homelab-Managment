# Scope: notes-archive-deploy

Triage: tweak + live — new guest cloned from the creative-archive pattern (`openspec/changes/archive/2026-11-01-creative-archive-deploy/`), live apply on merge. Appetite: one evening.

## Problem
Rue wants the Notes-Archive host and its check runner provisioned now, while the app is still in development, so the first release can go live as soon as it is tagged. Today this repo knows nothing about Notes-Archive.

## Flows
- Check runner: PR in Rue-Asha/Notes-Archive → job on `check01` with label `homelab-check` → proof runs.
- First rollout: merge → `plan` job shows one create → approve `infrastructure` → apply creates `notes-archive01` → deploy runs the playbook (fails until a release tag exists, accepted) → `fetch-inventory.sh` → `sqlite_backup.yml`.
- Release (later, once the app repo has CI): tag in the app repo → bump-pin PR here → merge → deploy → smoke check through nginx.

## In scope
- **S1** `terraform/environments/homelab/hosts.auto.tfvars` has a `notes-archive01` entry, group `notes_archive`, tags `["web","terraform"]`, address `192.168.0.231/24`, 2 cores / 4096 MB / 512 swap / 16 GB disk, with a comment giving the sizing reason and the playbook. `terraform fmt -check`, `validate` and `unique-hosts.py` pass.
  - edges: the commented-out `retropie01` block reserves .231 → it gets a note that the address moved to notes-archive01 and must pick a new one when revived; no `vmid` pinned (Proxmox assigns, `lxc_ctid` arrives via `scripts/fetch-inventory.sh`).
- **S2** Role `notes_archive` (cloned from `creative_archive`) and `ansible/playbooks/02_SERVICES/notes-archive.yml` (roles `common`, `nodejs`, `nginx`, `sqlite_snapshot`, `notes_archive`) install a release tarball from `https://github.com/Rue-Asha/Notes-Archive/releases/download/<tag>/notes-archive-<version-without-v>.tgz` (+ `.sha256`, format `<hex>  <name>.tgz`), flip `current`, restart, and end with a smoke check on `http://127.0.0.1/healthz` through nginx with rollback. Host vars pin `notes_archive_version: v0.1.0` as one plain unquoted line.
  - edges: env file sets `HOST=127.0.0.1`, `PORT=3000`, `DATABASE_PATH=/var/lib/notes-archive/notes-archive.db`, `PROTOCOL_HEADER=x-forwarded-proto`, `BODY_SIZE_LIMIT=17M`, and never `NOTES_ARCHIVE_TEST` or `MOCKUP_PHOTOS_DIR`; nginx `client_max_body_size` 18m stays above the app limit; WAL needs `/var/lib/notes-archive` writable by the service user; Node ≥ 22.18 for `node:sqlite` (the `nodejs` role pin must satisfy it); tarball top-level dir is `notes-archive-<version>/` with `build/`, `migrations/`, `package.json` and production `node_modules` (sharp) → the unpack step strips one level and migrations sit beside `package.json`; the app migrates on start, so there is no migrate task; the pin has no tag at PR time, so the first deploy fails until the tag exists (accepted, as for creative-archive).
- **S3** Backups and release plumbing are registered: `sqlite_backups` in the host vars (db `/var/lib/notes-archive/notes-archive.db`), `sqlite_snapshot` before the service role, `scripts/tests/sqlite-snapshot.sh` covers the new host, the release-bump spec and `docs/release-bump.md` list `notes_archive_version`, and `scripts/deploy-targets.sh` maps the new role and playbook (fixture test if the mapping needs one), and `deploy.yml` offers `notes-archive` in the `workflow_dispatch` choice list.
  - edges: the -wal/-shm files sit beside the db (the snapshot must use the SQLite online backup, not a file copy; check against `sqlite-backups/spec.md`); `lxc_ctid` is required for backups and only exists after the first apply (runbook step).
- **S4** `check_runner_repos` in `ansible/inventory/group_vars/check_runner/vars.yml` lists `Rue-Asha/Notes-Archive`, and `docs/check-runner.md` names it (repo list at the top, rollback bullet).
  - edges: registration (`check_runner.yml`) needs the workstation's `gh` login to have admin on the repo and the fork-PR approval set to "all external contributors", or the playbook fails naming the repo → runbook step, not run by flow; the app repo's `ci.yml` calling the shared proof workflow is in the split-off change.
- **S5** Docs, specs and the repo contract are updated: new `openspec/specs/notes-archive/spec.md` (delta spec), modified `release-bump` and `sqlite-backups` specs, a `README.md` roles-table row and playbook example line, `docs/backups.md` intro, a rollout runbook in the role README ("First rollout"), and the `## Specs` line in `.claude/CLAUDE.md` (written by the closer).
  - edges: the runbook states the app has no auth and the guest is reachable only on the LAN IP (and through the tailscale subnet router); post-merge steps live in the runbook and the manual checklist, not as a tasks.md unit.

## Non-goals
- Pi-hole DNS record, TLS, reverse proxy by name — LAN-only on the guest IP like creative-archive; the app has no auth, so no wider exposure.
- Notes-Archive `ci.yml` / `release.yml` / tarball-per-tag automation — lives in the app repo, which is still on its own flow branch (see Split off).
- Any change to the Notes-Archive repo — nothing here touches it.
- Applying Terraform or running a playbook — apply happens on `runner01` after merge, registration of the runner is run by Rue.
- Test routes (`/__test/*`) and mockup photos on the live host — must stay off.

## Codebase touchpoints
- `terraform/environments/homelab/hosts.auto.tfvars` — new entry + retropie01 note (explorer: Homelab recipe)
- `ansible/roles/creative_archive/` — template for `ansible/roles/notes_archive/` (explorer: Homelab recipe)
- `ansible/playbooks/02_SERVICES/`, `ansible/inventory/host_vars/`, `ansible/inventory/group_vars/check_runner/vars.yml` — new playbook, host vars, repo list entry (explorer: Homelab recipe)
- `.github/workflows/deploy.yml`, `scripts/tests/sqlite-snapshot.sh`, `scripts/deploy-targets.sh` — choice list, hardcoded hosts in the fixture, mapping check (explorer: Homelab recipe)
- `README.md`, `docs/backups.md`, `docs/release-bump.md`, `docs/check-runner.md`, `openspec/specs/{notes-archive,release-bump,sqlite-backups}/spec.md` — docs and specs (explorer: Homelab recipe)
- `Notes-Archive/README.md`, `vite.config.ts`, `scripts/package.mjs` — read-only source of env vars, port, tarball shape (explorer: Notes-Archive readiness)

## Risks
- R1 No tag/CI in Notes-Archive, so the first deploy after merge fails at download → accepted: same as creative-archive v0.1.0; terraform apply still creates the guest.
- R2 `scripts/package.mjs` uses `npm ci --ignore-scripts`, sharp's prebuilt binary may not arrive → accepted for this change, goes into the split-off brief (the release build must be checked on the target OS/arch).
- R3 Migrations apply by filename only, so editing 0001/0002 in place after the first deploy would not re-apply → accepted: app-side concern, noted in the role README (migrations must be additive, new files only).
- R4 No auth → resolved: LAN-only, no DNS, no TLS, documented in the runbook.
- R5 Provisioning a host for an unfinished app → accepted: Rue's decision, the guest costs 2 cores / 4 GB and can be destroyed with a `hosts.auto.tfvars` removal.
- R6 The `nodejs` role's pinned Node version may be below 22.18 → settle in planning (planner reads the role defaults); if so the bump is part of S2.

## Decisions
- Track tweak + live — a known recipe, one session; ship ≥ `pr` because the merge applies live infrastructure.
- Address 192.168.0.231 — Rue's pick, takes over retropie01's reservation.
- Exposure LAN-only on the guest IP — no auth in the app.
- Same sizing as creative-archive (2 cores / 4096 MB / 512 swap / 16 GB) — sharp plus images as BLOBs in SQLite.
- Check runner is a one-line entry — GitHub has no account-wide runners for a personal account.
- Rue-Asha/Notes-Archive is private today; Rue decided at the gate to make it public before the first tag — the role downloads release assets anonymously, no token auth is added. The runbook's anonymous curl on the asset URLs (step 2) is the gate, and the README names public visibility as a precondition.
- The stale `vmid = 231` in the commented-out retropie01 block is dropped together with the address note (task 1.1) — it is the IP-derived ID convention CLAUDE.md bans.
- Notes-Archive CI + release.yml was selected by Rue but is cut to Split off — different repo, still mid-build on `flow/build-notes-archive`, and it would be a sixth S-item; its brief is written to `split-off-notes-archive-ci.md` in this change dir.

## Done when
- `scripts/proof.sh --all` is green on `flow/notes-archive-deploy`.
- `terraform plan` shape is checkable from the diff: exactly one new guest, `notes-archive01`, at 192.168.0.231, nothing else changes.
- A reader of the role README can run the first rollout (tag check, merge, plan, approve, fetch-inventory, sqlite_backup, runner registration) without this conversation.
- Notes-Archive appears in `check_runner_repos`, `docs/check-runner.md`, the release-bump table and the backup registry.

## Split off
- Notes-Archive CI: `ci.yml` calling the shared proof workflow on `[self-hosted, homelab-check]`, `release.yml` building `notes-archive-<version>.tgz` + `.sha256` on `ubuntu-24.04` per tag and calling `Rue-Asha/ci` `bump-pin.yml` (`app`, `host_vars_path`, `variable: notes_archive_version`, `tag`, bot secrets). Done in the app repo after its build change lands, as its own change.
