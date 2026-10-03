life_manager
============

Deploys [Life Manager](https://github.com/Rue-Asha/Life-Manager) — a SvelteKit
(`adapter-node`) weekly-sprint todo app — onto a Proxmox LXC using the
build-on-host, app-per-LXC model (see `docs/party-games-webservice-architecture.md`).
The role checks out a **pinned version** of the app repo, builds it into a
timestamped release, flips an atomic `current` symlink, and supervises the
process with `systemd`.

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
| `life_manager_repo_url` | `""` | Git URL of the app repo. Set in host_vars. |
| `life_manager_version` | `main` | Pinned tag/commit to deploy (the "image tag"). |
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
2. Check out the pinned ref into `releases/<timestamp>`.
3. `npm ci` → `npm run build` → prune dev deps.
4. Flip `current` → the new release and restart the service.
5. The app applies its own migrations on start; a failing migration exits
   non-zero and shows up as a failed restart. `GET /healthz` answers `200 ok`
   once the database is open.
6. Prune all but the newest `life_manager_keep_releases` releases.

Use immutable tags or commit SHAs: redeploy is gated by a string comparison,
so a moving branch like `main` is never picked up again.

On-host layout
--------------

    /opt/life-manager/releases/<ts>/        built release
    /opt/life-manager/current ->            symlink to the active release
    /var/lib/life-manager/life-manager.db   SQLite — persists across redeploys
    /etc/life-manager/env                   HOST, PORT, NODE_ENV, DATABASE_PATH, PROTOCOL_HEADER

License
-------

MIT
