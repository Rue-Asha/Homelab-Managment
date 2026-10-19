rues_cooking_hub
================

Deploys [Rues Cooking Hub](https://github.com/Rue-Asha/Rues-Cooking-Hub) — a SvelteKit
(`adapter-node`) recipe app with SQLite storage, photos kept as BLOBs — onto a Proxmox LXC using the
app-per-LXC model (see `docs/party-games-webservice-architecture.md`).
The role downloads the **pinned release tarball** that the app's CI built and
tested, verifies its sha256, unpacks it into a timestamped release, flips an
atomic `current` symlink, and supervises the process with `systemd`. Nothing is
built on the host.

This role owns the *service* concerns only. The Node runtime (`nodejs`), the
reverse proxy (`nginx`) and base host config (`common`) are separate roles,
wired together by `playbooks/02_SERVICES/rues-cooking-hub.yml`.

Requirements
------------

- Debian (bookworm/trixie) LXC, base-configured by `common`.
- The `nodejs` role applied first. The app needs **Node >= 22.18** for `node:sqlite`.
- The `nginx` reverse proxy in front, sending `X-Forwarded-Proto` (it does by
  default). Without it every form post fails with a 403.

Role Variables
--------------

| Variable | Default | Description |
|---|---|---|
| `rues_cooking_hub_version` | `v0.1.0` | Release tag to deploy (the "image tag"). |
| `rues_cooking_hub_releases_url` | `…/Rues-Cooking-Hub/releases/download` | Base URL of the GitHub release assets. |
| `rues_cooking_hub_user` / `_group` | `rues-cooking-hub` | Unprivileged service account. |
| `rues_cooking_hub_base_dir` | `/opt/rues-cooking-hub` | Holds `releases/` and the `current` symlink. |
| `rues_cooking_hub_data_dir` | `/var/lib/rues-cooking-hub` | Persistent data. Never touched by a deploy. |
| `rues_cooking_hub_db_path` | `…/rues-cooking-hub.db` | SQLite database file (`DATABASE_PATH`). |
| `rues_cooking_hub_host` | `127.0.0.1` | Bind address; loopback keeps the backend behind nginx. |
| `rues_cooking_hub_port` | `3000` | Port the Node process listens on (match `nginx_backend_port`). |
| `rues_cooking_hub_protocol_header` | `x-forwarded-proto` | `PROTOCOL_HEADER` for adapter-node. |
| `rues_cooking_hub_body_size_limit` | `16M` | `BODY_SIZE_LIMIT` for adapter-node: largest request body, so photo uploads up to 15 MB get through. Keep it <= the host's `nginx_client_max_body_size` (`16m`), or nginx answers 413 first. |
| `rues_cooking_hub_keep_releases` | `5` | Releases to retain as rollback targets. |
| `rues_cooking_hub_smoke_url` | `http://127.0.0.1/healthz` | Requested after every run, through nginx on the host. |
| `rues_cooking_hub_smoke_headers` | `{}` | Set `Host` to `nginx_server_name`, or the request lands on nginx's default site. |
| `rues_cooking_hub_smoke_retries` / `_delay` | `10` / `3` | Start-up migrations must finish within retries × delay seconds. |

How a deploy works
------------------

1. Compare `rues_cooking_hub_version` with `current/.deployed_version`; if equal,
   the expensive steps are skipped.
2. Download `rues-cooking-hub-<X.Y.Z>.tgz` for the tag, verified against the
   release's `.sha256`, and unpack it into `releases/<timestamp>`. The tarball
   already holds `build/` and production `node_modules/`.
3. Flip `current` → the new release and restart the service.
4. The app applies its own migrations on start; a failing migration exits
   non-zero and shows up as a failed restart. `GET /healthz` answers `200 ok`
   once the database is open.
5. Smoke check (`tasks/verify.yml`), on every run: flush handlers so the
   restart has happened, then request `rues_cooking_hub_smoke_url` until it
   answers 2xx. If it never does and this run swapped `current`, `current` is
   pointed back at the release that was active before the run, the service is
   restarted on it, and the play fails naming both releases. With no previous
   release (first deploy) or no swap, the play just fails.
6. Prune all but the newest `rues_cooking_hub_keep_releases` releases. This runs
   after the check, so pruning never removes the rollback target.

**Rollback restores code, not data.** Migrations run forward only, so a rolled
back release starts against a database the failed release may already have
migrated. Rues Cooking Hub migrations must therefore stay additive: an old release
has to run on a newer schema.

Redeploy is gated by a string comparison against the tag, so re-running with
the same tag never re-fetches.

On-host layout
--------------

    /opt/rues-cooking-hub/releases/<ts>/        unpacked release tarball
    /opt/rues-cooking-hub/current ->            symlink to the active release
    /var/lib/rues-cooking-hub/rues-cooking-hub.db   SQLite — persists across redeploys
    /etc/rues-cooking-hub/env                   HOST, PORT, NODE_ENV, DATABASE_PATH, PROTOCOL_HEADER, BODY_SIZE_LIMIT

Plain HTTP
----------

The guest is served as `http://192.168.0.228`: no DNS name, no TLS. The browser
treats that origin as not a secure context, so the app cannot use a service
worker, Wake Lock or the clipboard API.

First rollout
-------------

Steps marked ⚠ change live systems. Merging deploys, and flow never merges this
change: Rue merges after the tag exists.

1. On `runner01`, `ssh-keygen -F 192.168.0.228` must find nothing. If it
   prints a key, remove the stale entry first (`ssh-keygen -R 192.168.0.228`):
   `scripts/tf-ci.sh apply` skips the keyscan for an address it already knows,
   and the new guest's key would never be trusted. (spec: "A stale host key
   would block the apply")
2. Tag `v0.1.0` exists in `Rue-Asha/Rues-Cooking-Hub` with the assets
   `rues-cooking-hub-0.1.0.tgz` and `rues-cooking-hub-0.1.0.tgz.sha256`.
   Merging earlier fails the first deploy at the fetch task, before `current`
   exists. (spec: "Merging before the tag fails the first deploy")
3. ⚠ Merge the PR. (spec: "The first deploy runs the new playbook once")
4. Read the `plan` job log: exactly one create, `module.lxc["rues-cooking-hub01"]`,
   and nothing else. Then ⚠ approve the `infrastructure` environment.
   (spec: "The runner plan shows exactly one new container")
5. The `deploy` job lists `02_SERVICES/rues-cooking-hub.yml` once, and its smoke
   check passes. `curl -i http://192.168.0.228/healthz` answers 200.
   (spec: "The first deploy comes up healthy")
6. From the workstation, `scripts/fetch-inventory.sh`, then
   `ansible-inventory --graph` must show `rues-cooking-hub01` under
   `rues_cooking_hub` -> `lxc_container_proxmox` -> `proxmox_guest`, with an
   `lxc_ctid`. (spec: "rues-cooking-hub01 chains to proxmox_guest")
7. Register the database with the nightly backup, from the workstation:
   `ansible-playbook ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml --check`,
   then ⚠ the same command without `--check`. Until then only the pre-deploy
   snapshots on the guest cover the database. (spec: "The database joins the
   nightly backup")
8. Next morning `journalctl -u homelab-sqlite-backup.service` on proxmox1 logs
   `rues-cooking-hub01: ok`.

The app's `v0.1.0` bump job fails on the missing
`ansible/inventory/host_vars/rues-cooking-hub01/vars.yml` (it was not on `main`
when the tag was cut). That is accepted and needs nothing. Later tags bump the
pin by themselves (`docs/release-bump.md`).

License
-------

MIT
