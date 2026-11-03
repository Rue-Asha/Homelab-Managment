## Why

Rue wants the Notes-Archive host and its check runner provisioned now, while the app is still in development, so the first release can go live as soon as it is tagged. Today this repo knows nothing about Notes-Archive.

Appetite: one evening.

## What Changes

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

## Non-Goals

- Pi-hole DNS record, TLS, reverse proxy by name — LAN-only on the guest IP like creative-archive; the app has no auth, so no wider exposure.
- Notes-Archive `ci.yml` / `release.yml` / tarball-per-tag automation — lives in the app repo, which is still on its own flow branch (see `split-off-notes-archive-ci.md`).
- Any change to the Notes-Archive repo — nothing here touches it.
- Applying Terraform or running a playbook — apply happens on `runner01` after merge, registration of the runner is run by Rue.
- Test routes (`/__test/*`) and mockup photos on the live host — must stay off.

## Decisions

- Track tweak + live — a known recipe, one session; ship ≥ `pr` because the merge applies live infrastructure.
- Address 192.168.0.231 — Rue's pick, takes over retropie01's reservation.
- Exposure LAN-only on the guest IP — no auth in the app.
- Same sizing as creative-archive (2 cores / 4096 MB / 512 swap / 16 GB) — sharp plus images as BLOBs in SQLite.
- Check runner is a one-line entry — GitHub has no account-wide runners for a personal account.
- Notes-Archive CI + release.yml was selected by Rue but is cut to Split off — different repo, still mid-build on `flow/build-notes-archive`, and it would be a sixth S-item; its brief is written to `split-off-notes-archive-ci.md` in this change dir.
- R6 settled in planning (no bump): the `nodejs` role installs from NodeSource `node_{{ nodejs_version }}.x` with `nodejs_version: "22"` and `state: present`, so a fresh guest gets the newest 22.x the repo serves, which is past 22.18 (released 2025-07). `creative-archive01` has the same `>=22.18` requirement (its role README) and is deployed with this role unchanged (bumps to v0.1.1 and v0.1.2 merged). The default is shared by all four service playbooks, so it stays untouched; the post-merge `node --version` check on `notes-archive01` is the evidence.
- Rue-Asha/Notes-Archive is private today; Rue decided at the gate to make it public before the first tag — the role downloads release assets anonymously, no token auth is added. The runbook's anonymous curl on the asset URLs (step 2) is the gate, and the role README names public visibility as a precondition. A private repo makes every deploy fail at the fetch task.
- The stale `vmid = 231` in the commented-out retropie01 block is dropped together with the address note (task 1.1) — it is the IP-derived ID convention CLAUDE.md bans.
- nginx needs no variable beyond creative-archive's set (`nginx_reverse_proxy_enabled`, backend host/port, `nginx_service_description`, `nginx_client_max_body_size: 18m`, plus `notes_archive_smoke_headers` with `Host`); no shared role changes.
- `scripts/deploy-targets.sh` needs no change and no fixture: it globs `02_SERVICES/*.yml` and maps roles, host_vars and group_vars generically; its fixtures build their own inventory and hardcode no real host.

## Risks

- R1 No tag/CI in Notes-Archive, so the first deploy after merge fails at download → accepted: same as creative-archive v0.1.0; terraform apply still creates the guest.
- R2 `scripts/package.mjs` uses `npm ci --ignore-scripts`, sharp's prebuilt binary may not arrive → accepted for this change, goes into the split-off brief.
- R3 Migrations apply by filename only, so editing 0001/0002 in place after the first deploy would not re-apply → accepted: app-side concern, noted in the role README (migrations must be additive, new files only).
- R4 No auth → resolved: LAN-only, no DNS, no TLS, documented in the runbook.
- R5 Provisioning a host for an unfinished app → accepted: Rue's decision; the guest can be destroyed with a `hosts.auto.tfvars` removal.
- R6 → settled above, no bump.

## Done criteria

- [ ] `scripts/proof.sh --all` is green on `flow/notes-archive-deploy`.
- [ ] `terraform plan` shape is checkable from the diff: exactly one new guest, `notes-archive01`, at 192.168.0.231, nothing else changes (`git diff main...HEAD -- terraform/` adds one `lxc_hosts` entry and edits only the retropie01 comment: address note added, `vmid = 231` dropped).
- [ ] A reader of `ansible/roles/notes_archive/README.md` can run the first rollout (tag check, merge, plan, approve, fetch-inventory, sqlite_backup, runner registration) without this conversation.
- [ ] Notes-Archive appears in `check_runner_repos`, `docs/check-runner.md`, the release-bump table and the backup registry.

## Where the plan is visible

CI (`ci.yml`) runs `proof.sh --all` on the PR, which covers `terraform fmt -check`, `validate`, `tflint` and `checkov`, but never `terraform plan`: neither the workstation nor CI holds state. The only plan is the `plan` job of the `deploy` workflow on `runner01`, after the merge, and it waits for the `infrastructure` approval before `apply`. Pre-merge dry-run evidence is therefore `terraform fmt -check` + `validate`, `ansible-playbook --syntax-check`, and the diff of `hosts.auto.tfvars`; a `--check` run needs the guest, which only exists after the apply.

## First rollout (runbook, after the PR is green)

Not tasks. Rue does these; the verifier copies them into `verification.md` as the post-merge checklist, together with every `manual (post-merge …)` scenario. The same steps live in `ansible/roles/notes_archive/README.md` → "First rollout". ⚠ marks steps that change live systems.

1. On `runner01`, `ssh-keygen -F 192.168.0.231` finds nothing; else `ssh-keygen -R 192.168.0.231` first (`scripts/tf-ci.sh apply` skips the keyscan for an address it already knows; .231 was retropie01's address, so a stale key is plausible).
2. Tag and visibility gate: `Rue-Asha/Notes-Archive` MUST be public before the first tag (it is private today). `curl -fsSIL https://github.com/Rue-Asha/Notes-Archive/releases/download/v0.1.0/notes-archive-0.1.0.tgz` and the same URL with `.sha256` answer 200 without a login. A private repo answers 404 here and makes every deploy fail at the fetch task: the role adds no token auth. If the assets are missing (repo public, tag not yet cut), merging is still Rue's call (R1): the guest is created and the deploy fails at the fetch task; step 7 then brings the release live later.
3. ⚠ Merge the PR.
4. Read the `plan` job log: exactly one create, `module.lxc["notes-archive01"]`, nothing else. Then ⚠ approve `infrastructure` (apply creates the container).
5. The `deploy` job lists `02_SERVICES/notes-archive.yml` once. With the tag, its smoke check passes and `http://192.168.0.231/healthz` answers 200; without it, the run fails at the fetch task (accepted).
6. From the workstation: `scripts/fetch-inventory.sh`, then `ansible-inventory --graph` shows `notes-archive01` under `notes_archive` → `lxc_container_proxmox` → `proxmox_guest` with an `lxc_ctid`.
7. Only if step 5 failed for a missing tag: once `v0.1.0` is published, ⚠ dispatch `deploy.yml` with playbook `notes-archive`. The app's first bump job has nothing to do (the pin already equals `v0.1.0`), so no bump PR deploys it.
8. Only after a healthy deploy (the database exists): `ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml --check`, then ⚠ without `--check`. Registering earlier makes every nightly run fail on the missing database.
9. Next morning the nightly run on proxmox1 logs `notes-archive01: ok`.
10. Check runner, any time after the merge: the workstation's `gh` login has admin on `Rue-Asha/Notes-Archive` and its fork-PR approval is "all external contributors"; `ansible-playbook ansible/playbooks/01_BASE_CONFIGURATION/check_runner.yml --check`, then ⚠ without `--check`; the repo's Settings → Actions → Runners shows the instance online with label `homelab-check`. Jobs arrive only once the split-off `ci.yml` lands.

The app has no auth: the guest is reachable only on `http://192.168.0.231` in the LAN and through the tailscale subnet router, with no DNS name and no TLS.

## Capabilities

### New Capabilities
- `notes-archive`: the `notes-archive01` guest, the `notes_archive` role, its `02_SERVICES` playbook and host_vars, the upload size limits, the manual-dispatch entry, the check-runner entry, the docs and the rollout runbook.

### Modified Capabilities
- `release-bump`: adds the per-app requirement that this repo holds `notes_archive_version` in `host_vars/notes-archive01/vars.yml` as a bumpable line, listed under wired-up apps.
- `sqlite-backups`: MODIFIED "One registry entry per service host drives every backup step" (names Notes-Archive, unit-checked by `scripts/tests/sqlite-snapshot.sh`) and MODIFIED "Service playbooks snapshot the database before the service role runs" (same for the playbook order, plus the WAL online-backup edge); ADDED "The Notes-Archive database joins the nightly backup".

## Impact

- New: `ansible/roles/notes_archive/`, `ansible/playbooks/02_SERVICES/notes-archive.yml`, `ansible/inventory/host_vars/notes-archive01/vars.yml`.
- Changed: `terraform/environments/homelab/hosts.auto.tfvars` (one new guest, retropie01 comment: address note, `vmid = 231` dropped), `.github/workflows/deploy.yml` (one choice), `ansible/inventory/group_vars/check_runner/vars.yml` (one repo), `scripts/tests/sqlite-snapshot.sh` (two new checks), `README.md`, `docs/backups.md`, `docs/release-bump.md`, `docs/check-runner.md`; `.claude/CLAUDE.md` (one `## Specs` line) by the closer at archive.
- Unchanged and relied on: `scripts/deploy-targets.sh` and `scripts/tests/deploy-targets.sh`, `scripts/checks/unique-hosts.py` and `scripts/tests/unique-hosts.sh`, `scripts/proof.sh`, the `nginx`, `nodejs`, `common`, `sqlite_snapshot` roles.
- Live systems, on Rue's merge only: Proxmox node (new LXC), the new guest (service deploy), proxmox1's nightly backup config and `check01`'s runner instances (after the manual runbook steps).
