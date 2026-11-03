notes_archive
=============

Deploys [Notes Archive](https://github.com/Rue-Asha/Notes-Archive) — a SvelteKit
(`adapter-node`) single-user notes archive with folders, tags, full-text search
and a block editor, backed by SQLite with images kept as BLOBs — onto a Proxmox
LXC using the app-per-LXC model (see `docs/party-games-webservice-architecture.md`).
The role downloads the **pinned release tarball** that the app's CI built and
tested, verifies its sha256, unpacks it into a timestamped release, flips an
atomic `current` symlink, and supervises the process with `systemd`. Nothing is
built on the host.

This role owns the *service* concerns only. The Node runtime (`nodejs`), the
reverse proxy (`nginx`) and base host config (`common`) are separate roles,
wired together by `playbooks/02_SERVICES/notes-archive.yml`.

Requirements
------------

- Debian (bookworm/trixie) LXC, base-configured by `common`.
- The `nodejs` role applied first. The app needs **Node >= 22.18** for `node:sqlite`.
- The `nginx` reverse proxy in front, sending `X-Forwarded-Proto` (it does by
  default). Without it every form post fails with a 403.
- **`Rue-Asha/Notes-Archive` MUST be public before the first tag.** The role
  downloads the release assets anonymously and adds no download credentials, so a private
  repo answers 404 and every deploy fails at the fetch task.

Role Variables
--------------

| Variable | Default | Description |
|---|---|---|
| `notes_archive_version` | `v0.1.0` | Release tag to deploy (the "image tag"). |
| `notes_archive_releases_url` | `…/Notes-Archive/releases/download` | Base URL of the GitHub release assets. |
| `notes_archive_user` / `_group` | `notes-archive` | Unprivileged service account. |
| `notes_archive_base_dir` | `/opt/notes-archive` | Holds `releases/` and the `current` symlink. |
| `notes_archive_data_dir` | `/var/lib/notes-archive` | Persistent data. Never touched by a deploy. |
| `notes_archive_db_path` | `…/notes-archive.db` | SQLite database file (`DATABASE_PATH`). |
| `notes_archive_host` | `127.0.0.1` | Bind address; loopback keeps the backend behind nginx. |
| `notes_archive_port` | `3000` | Port the Node process listens on (match `nginx_backend_port`). |
| `notes_archive_protocol_header` | `x-forwarded-proto` | `PROTOCOL_HEADER` for adapter-node. |
| `notes_archive_body_size_limit` | `17M` | `BODY_SIZE_LIMIT` for adapter-node: largest request body, so image uploads up to 16 MB get through. Keep it below the host's `nginx_client_max_body_size` (`18m`), or nginx answers 413 first. |
| `notes_archive_keep_releases` | `5` | Releases to retain as rollback targets. |
| `notes_archive_smoke_url` | `http://127.0.0.1/healthz` | Requested after every run, through nginx on the host. |
| `notes_archive_smoke_headers` | `{}` | Set `Host` to `nginx_server_name`, or the request lands on nginx's default site. |
| `notes_archive_smoke_retries` / `_delay` | `10` / `3` | Start-up migrations must finish within retries × delay seconds. |

How a deploy works
------------------

1. Compare `notes_archive_version` with `current/.deployed_version`; if equal,
   the expensive steps are skipped.
2. Download `notes-archive-<X.Y.Z>.tgz` for the tag, verified against the
   release's `.sha256`, and unpack it into `releases/<timestamp>`. The tarball
   wraps everything in `notes-archive-<X.Y.Z>/`, stripped on unpack, and holds
   `build/`, `migrations/`, `package.json` and production `node_modules/`.
3. Flip `current` → the new release and restart the service.
4. The app applies its own migrations on start; a failing migration exits
   non-zero and shows up as a failed restart. `GET /healthz` answers `200 ok`
   once the database is open.
5. Smoke check (`tasks/verify.yml`), on every run: flush handlers so the
   restart has happened, then request `notes_archive_smoke_url` until it
   answers 2xx. If it never does and this run swapped `current`, `current` is
   pointed back at the release that was active before the run, the service is
   restarted on it, and the play fails naming both releases. With no previous
   release (first deploy) or no swap, the play just fails.
6. Prune all but the newest `notes_archive_keep_releases` releases. This runs
   after the check, so pruning never removes the rollback target.

**Rollback restores code, not data.** Migrations run forward only, so a rolled
back release starts against a database the failed release may already have
migrated. Notes Archive migrations must therefore stay additive, as new files
only: an old release has to run on a newer schema, and editing an applied
migration in place is never re-applied.

Redeploy is gated by a string comparison against the tag, so re-running with
the same tag never re-fetches.

On-host layout
--------------

    /opt/notes-archive/releases/<ts>/        unpacked release tarball
    /opt/notes-archive/current ->            symlink to the active release
    /var/lib/notes-archive/notes-archive.db  SQLite — persists across redeploys
    /etc/notes-archive/env                   HOST, PORT, NODE_ENV, DATABASE_PATH, PROTOCOL_HEADER, BODY_SIZE_LIMIT

Plain HTTP
----------

The guest is served as `http://192.168.0.231`: no DNS name, no TLS. The app has
**no auth**, so the guest is reachable only on that LAN IP and through the
tailscale subnet router, nowhere else. The browser treats the plain-HTTP origin
as not a secure context, so the app cannot use a service worker, Wake Lock or
the clipboard API.

First rollout
-------------

Steps marked ⚠ change live systems. Merging deploys, and flow never merges this
change: Rue merges after the tag exists, or accepts a failing first deploy
(step 2). The `plan` job of `deploy.yml` is the only place the terraform plan
appears; CI runs no plan. (spec: "The runbook lists the steps in order", "The
runbook states the exposure")

1. On `runner01`, `ssh-keygen -F 192.168.0.231` must find nothing. If it
   prints a key, remove the stale entry first (`ssh-keygen -R 192.168.0.231`):
   `scripts/tf-ci.sh apply` skips the keyscan for an address it already knows,
   and `.231` was retropie01's address, so a stale key is plausible. (spec: "A
   stale host key would block the apply")
2. Visibility and tag gate: `Rue-Asha/Notes-Archive` MUST be public before the
   first tag. `curl -fsSIL https://github.com/Rue-Asha/Notes-Archive/releases/download/v0.1.0/notes-archive-0.1.0.tgz`
   and the same URL with `.sha256` appended must answer 200 without a login; a
   private repo answers 404. If the assets are missing (repo public, tag not
   yet cut), merging is still Rue's call: the guest is created and the deploy
   fails at the fetch task, before `current` exists; step 7 brings the release
   live later. (spec: "The release assets are public before the first tag",
   "Merging before the tag fails the first deploy")
3. ⚠ Merge the PR. (spec: "The first deploy runs the new playbook once")
4. Read the `plan` job log of `deploy.yml`: exactly one create,
   `module.lxc["notes-archive01"]`, and nothing else. Then ⚠ approve the
   `infrastructure` environment. (spec: "The runner plan shows exactly one new
   container")
5. The `deploy` job lists `02_SERVICES/notes-archive.yml` once. With the tag
   published its smoke check passes and `curl -i http://192.168.0.231/healthz`
   answers 200; without it the run fails at the fetch task (accepted).
   (spec: "The first deploy comes up healthy")
6. From the workstation, `scripts/fetch-inventory.sh`, then
   `ansible-inventory --graph` must show `notes-archive01` under
   `notes_archive` -> `lxc_container_proxmox` -> `proxmox_guest`, with an
   `lxc_ctid`. (spec: "notes-archive01 chains to proxmox_guest")
7. Only if step 5 failed for a missing tag: once `v0.1.0` is published, ⚠
   dispatch `deploy.yml` with playbook `notes-archive`. The app's first bump
   job has nothing to do (the pin already equals `v0.1.0`), so no bump PR
   deploys it. (spec: "A first release equal to the pin goes live by dispatch")
8. Only after a healthy deploy (the database exists), register the database
   with the nightly backup, from the workstation:
   `ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml --check`,
   then ⚠ the same command without `--check`. Registering earlier makes every
   nightly run fail on the missing database. (spec: "The Notes-Archive database
   joins the nightly backup", "Registering before the first healthy deploy fails
   the nightly run")
9. Next morning `journalctl -u homelab-sqlite-backup.service` on proxmox1 logs
   `notes-archive01: ok`. (spec: "The Notes-Archive database joins the nightly
   backup")
10. Check runner, any time after the merge: the workstation's `gh` login has
    admin on `Rue-Asha/Notes-Archive` and the repo's fork-PR approval is "all
    external contributors", otherwise the play fails naming the repo. Run
    `ansible-playbook ansible/playbooks/01_BASE_CONFIGURATION/check_runner.yml --check`,
    then ⚠ without `--check`; the repo's Settings → Actions → Runners shows the
    instance online with label `homelab-check`. Jobs arrive only once the app
    repo's `ci.yml` calls the shared proof workflow. (spec: "Registration
    without the fork-approval policy fails naming the repo", "The Notes-Archive
    runner comes online")

Later tags bump the pin by themselves (`docs/release-bump.md`).

License
-------

MIT
