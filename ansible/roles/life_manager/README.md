life_manager
============

Deploys [Life Manager](https://github.com/Rue-Asha/Life-Manager) — a SvelteKit
(`adapter-node`) weekly-sprint todo app — onto a Proxmox LXC using the
app-per-LXC model (see `docs/party-games-webservice-architecture.md`).
The role downloads the **pinned release tarball** that the app's CI built and
tested, verifies its sha256, unpacks it into a timestamped release, flips an
atomic `current` symlink, and supervises the process with `systemd`. Nothing is
built on the host.

This role owns the *service* concerns only. The Node runtime (`nodejs`), the
reverse proxy (`nginx`) and base host config (`common`) are separate roles,
wired together by `playbooks/03_SERVICES/life-manager.yml`.

Requirements
------------

- Debian (bookworm/trixie) LXC, base-configured by `common`.
- The `nodejs` role applied first. The app needs **Node >= 22.5** for `node:sqlite`.
- The `nginx` reverse proxy in front, sending `X-Forwarded-Proto` (it does by
  default). Without it every form post fails with a 403.

Role Variables
--------------

| Variable | Default | Description |
|---|---|---|
| `life_manager_version` | `v0.2.0` | Release tag to deploy (the "image tag"). |
| `life_manager_releases_url` | `…/Life-Manager/releases/download` | Base URL of the GitHub release assets. |
| `life_manager_user` / `_group` | `life-manager` | Unprivileged service account. |
| `life_manager_base_dir` | `/opt/life-manager` | Holds `releases/` and the `current` symlink. |
| `life_manager_data_dir` | `/var/lib/life-manager` | Persistent data. Never touched by a deploy. |
| `life_manager_db_path` | `…/life-manager.db` | SQLite database file (`DATABASE_PATH`). |
| `life_manager_host` | `127.0.0.1` | Bind address; loopback keeps the backend behind nginx. |
| `life_manager_port` | `3000` | Port the Node process listens on (match `nginx_backend_port`). |
| `life_manager_protocol_header` | `x-forwarded-proto` | `PROTOCOL_HEADER` for adapter-node. |
| `life_manager_keep_releases` | `5` | Releases to retain as rollback targets. |

How a deploy works
------------------

1. Compare `life_manager_version` with `current/.deployed_version`; if equal,
   the expensive steps are skipped.
2. Download `life-manager-<X.Y.Z>.tgz` for the tag, verified against the
   release's `.sha256`, and unpack it into `releases/<timestamp>`. The tarball
   already holds `build/` and production `node_modules/`.
3. Flip `current` → the new release and restart the service.
4. The app applies its own migrations on start; a failing migration exits
   non-zero and shows up as a failed restart. `GET /healthz` answers `200 ok`
   once the database is open.
5. Prune all but the newest `life_manager_keep_releases` releases.

Redeploy is gated by a string comparison against the tag, so re-running with
the same tag never re-fetches.

On-host layout
--------------

    /opt/life-manager/releases/<ts>/        unpacked release tarball
    /opt/life-manager/current ->            symlink to the active release
    /var/lib/life-manager/life-manager.db   SQLite — persists across redeploys
    /etc/life-manager/env                   HOST, PORT, NODE_ENV, DATABASE_PATH, PROTOCOL_HEADER

License
-------

MIT
