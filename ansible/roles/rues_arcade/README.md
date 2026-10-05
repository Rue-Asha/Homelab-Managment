rues_arcade
===========

Deploys [Rues Arcade](https://github.com/Rue-Asha/Rues-Arcade) — a SvelteKit
(`adapter-node`) browser-games — onto a Proxmox LXC using the
app-per-LXC model (see `docs/party-games-webservice-architecture.md`).
The role downloads the **pinned release tarball** that the app's CI built and
tested, verifies its sha256, unpacks it into a timestamped release, flips an
atomic `current` symlink, and supervises the process with `systemd`. Nothing is
built on the host.

This role owns the *service* concerns only. The Node runtime (`nodejs`), the
reverse proxy (`nginx`) and base host config (`common`) are separate roles,
wired together by `playbooks/03_SERVICES/rues-arcade.yml`.

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
| `rues_arcade_version` | `v0.2.0` | Release tag to deploy (the "image tag"). |
| `rues_arcade_releases_url` | `…/Rues-Arcade/releases/download` | Base URL of the GitHub release assets. |
| `rues_arcade_user` / `_group` | `rues-arcade` | Unprivileged service account. |
| `rues_arcade_base_dir` | `/opt/rues-arcade` | Holds `releases/` and the `current` symlink. |
| `rues_arcade_data_dir` | `/var/lib/rues-arcade` | Persistent data. Never touched by a deploy. |
| `rues_arcade_db_path` | `…/rues-arcade.db` | SQLite database file (`DATABASE_PATH`). |
| `rues_arcade_host` | `127.0.0.1` | Bind address; loopback keeps the backend behind nginx. |
| `rues_arcade_port` | `3000` | Port the Node process listens on (match `nginx_backend_port`). |
| `rues_arcade_protocol_header` | `x-forwarded-proto` | `PROTOCOL_HEADER` for adapter-node. |
| `rues_arcade_keep_releases` | `5` | Releases to retain as rollback targets. |
| `rues_arcade_smoke_url` | `http://127.0.0.1/healthz` | Requested after every run, through nginx on the host. |
| `rues_arcade_smoke_headers` | `{}` | Set `Host` to `nginx_server_name`, or the request lands on nginx's default site. |
| `rues_arcade_smoke_retries` / `_delay` | `10` / `3` | Start-up migrations must finish within retries × delay seconds. |

How a deploy works
------------------

1. Compare `rues_arcade_version` with `current/.deployed_version`; if equal,
   the expensive steps are skipped.
2. Download `rues-arcade-<X.Y.Z>.tgz` for the tag, verified against the
   release's `.sha256`, and unpack it into `releases/<timestamp>`. The tarball
   already holds `build/` and production `node_modules/`.
3. Flip `current` → the new release and restart the service.
4. The app applies its own migrations on start; a failing migration exits
   non-zero and shows up as a failed restart. `GET /healthz` answers `200 ok`
   once the database is open.
5. Smoke check (`tasks/verify.yml`), on every run: flush handlers so the
   restart has happened, then request `rues_arcade_smoke_url` until it
   answers 2xx. If it never does and this run swapped `current`, `current` is
   pointed back at the release that was active before the run, the service is
   restarted on it, and the play fails naming both releases. With no previous
   release (first deploy) or no swap, the play just fails.
6. Prune all but the newest `rues_arcade_keep_releases` releases. This runs
   after the check, so pruning never removes the rollback target.

**Rollback restores code, not data.** Migrations run forward only, so a rolled
back release starts against a database the failed release may already have
migrated. Rues Arcade migrations must therefore stay additive: an old release
has to run on a newer schema.

Redeploy is gated by a string comparison against the tag, so re-running with
the same tag never re-fetches.

On-host layout
--------------

    /opt/rues-arcade/releases/<ts>/        unpacked release tarball
    /opt/rues-arcade/current ->            symlink to the active release
    /var/lib/rues-arcade/rues-arcade.db   SQLite — persists across redeploys
    /etc/rues-arcade/env                   HOST, PORT, NODE_ENV, DATABASE_PATH, PROTOCOL_HEADER

License
-------

MIT
