life-dashboard
==============

Deploys the **Life-Management-Dashboard** ("Zentrale") SvelteKit
(`adapter-node`) web service onto a Proxmox LXC using the build-on-host,
app-per-LXC model (see `docs/party-games-webservice-architecture.md`). The role
checks out a **pinned version** of the separate
[`Life-Managment-Dashboard`](https://github.com/Rue-Asha/Life-Managment-Dashboard)
app repo, builds it into a timestamped release, applies DB migrations, flips an
atomic `current` symlink, and supervises the process with `systemd`.

The app is a single-user personal dashboard (budget, uni tasks, schedule board,
notes, a read-only calendar agenda) reachable **only from the homelab LAN or
over VPN** — it holds sensitive personal and financial data and is never exposed
to the public internet.

This role owns the *service* concerns only. It does **not** install the Node
runtime (the `nodejs` role) or the reverse proxy (the `nginx` role) or manage the
firewall (host-level). The `03_SERVICES` play wires the three roles together.

> **History.** The service was first deployed under a `budget` identity, back
> when the app was a standalone Budgeting-Web-App. The dashboard absorbed that
> app, so the role was renamed `budget` → `life-dashboard`. On the first deploy
> the role migrates the old on-host layout in place — see
> [Legacy migration](#legacy-migration).

Requirements
------------

- Debian (bookworm/trixie) LXC, base-configured by `common`.
- The `nodejs` role applied first (Node >= 22, for built-in `node:sqlite`).
- An `nginx` reverse proxy in front (`:80` -> `127.0.0.1:{{ life_dashboard_port }}`).
- The separate **Life-Management-Dashboard app repo** must exist and be buildable
  (`npm ci && npm run build`, `adapter-node` output in `build/`).
- A read-only **deploy key** for the (private) app repo, supplied via vault.

Role Variables
--------------

| Variable | Default | Description |
|---|---|---|
| `life_dashboard_repo_url` | `""` | Git URL of the app repo. Set in host_vars. |
| `life_dashboard_version` | `main` | Pinned tag/branch/commit to deploy (the "image tag"). |
| `life_dashboard_deploy_key` | `""` | Private deploy-key contents (from vault). Empty skips key install. |
| `life_dashboard_user` / `_group` | `life-dashboard` | Unprivileged service account. |
| `life_dashboard_base_dir` | `/opt/life-dashboard` | Holds `releases/` and the `current` symlink. |
| `life_dashboard_data_dir` | `/var/lib/life-dashboard` | Persistent data; holds `app.db`. Never wiped by a deploy. |
| `life_dashboard_config_dir` | `/etc/life-dashboard` | Env file and deploy key. |
| `life_dashboard_db_path` | `…/app.db` | SQLite database file. |
| `life_dashboard_images_dir` | `…/images` | Uploaded images (`IMAGES_DIR`); on the filesystem, not in the DB. Keep it under `life_dashboard_data_dir`, or add it to the unit's `ReadWritePaths`. |
| `life_dashboard_host` | `127.0.0.1` | Bind address for the adapter-node server. Loopback keeps the backend reachable only via the nginx proxy, never directly on the LAN. |
| `life_dashboard_port` | `3000` | Port the Node process listens on (match `nginx_backend_port`). |
| `life_dashboard_node_env` | `production` | `NODE_ENV` for runtime/migrations. |
| `life_dashboard_origin` | `http://{{ ansible_host }}` | Browser-facing URL (`ORIGIN`). SvelteKit's CSRF check rejects form POSTs whose `Origin` header doesn't match. |
| `life_dashboard_build_command` | `npm run build` | Build command run in the release dir. |
| `life_dashboard_migrate_command` | `npm run db:migrate` | Migration command; override per app, or `""` to disable. |
| `life_dashboard_keep_releases` | `5` | Releases to retain as rollback targets. |
| `life_dashboard_migrate_legacy` | `true` | Run the one-time `budget` → `life-dashboard` handover. Set `false` once no host carries the old layout. |

How a deploy works
------------------

1. Read the live version from `current/.deployed_version`.
2. If it differs from `life_dashboard_version`, a redeploy is needed; otherwise
   the expensive steps are skipped (idempotent).
3. Checkout the pinned ref into `releases/<timestamp>` (using the deploy key).
4. `npm ci` -> `npm run build` -> prune dev deps.
5. Run migrations against `/var/lib/life-dashboard/app.db`.
6. Flip `current` -> the new release (atomic) and restart the service.
7. Prune all but the newest `life_dashboard_keep_releases` releases.

**Rollback:** repoint `current` at a previous release (or re-run pinned to the
old version) and restart.

Releasing a new version
-----------------------

The app lives in its own repo and is decoupled from this host config: change app
code freely without touching the homelab repo, as long as the app keeps honoring
the build contract (`npm ci && npm run build` -> `build/`; `node build` reads
`HOST`/`PORT`/`ORIGIN`/`DATABASE_PATH`/`IMAGES_DIR`; `npm run db:migrate` applies
migrations; Node >= 22). The unit of release is a **pinned git ref** — the
equivalent of an image tag.

Normal release loop:

    # 1. In the app repo: commit, then tag an immutable release
    git tag v1.2.0 && git push origin v1.2.0

    # 2. In this repo: point the host at the new tag
    #    inventory/host_vars/life-dashboard01/vars.yml
    life_dashboard_version: v1.2.0

    # 3. Deploy
    ansible-playbook playbooks/03_SERVICES/life-dashboard.yml

The role builds the new ref into a fresh `releases/<ts>`, runs any new migrations
against the persistent `app.db`, atomically flips `current`, and restarts the
service. Persistent data in `/var/lib/life-dashboard/` is never touched; downtime
is just the restart.

One-off without editing host_vars (handy for testing a tag):

    ansible-playbook playbooks/03_SERVICES/life-dashboard.yml -e life_dashboard_version=v1.2.0

**Use immutable tags or commit SHAs, and bump them each release.** Redeploy is
gated by a *string* comparison between the requested `life_dashboard_version` and
the last-deployed one (recorded in `current/.deployed_version`). Pinning to a
moving branch (e.g. `main`) is sticky: the string never changes, so new commits
are **not** picked up. A new tag/commit is what triggers a rebuild.

Legacy migration
----------------

`migrate_legacy.yml` performs a one-time, idempotent handover from the former
`budget` identity, gated on `life_dashboard_migrate_legacy` (default `true`). It
runs after the service user is created and **before** the new directory layout,
so the persistent database is relocated before an empty new data dir can shadow
it. On a host that still carries the old layout it:

1. Stops, disables, and removes the legacy `budget.service` unit (`daemon-reload`).
2. Moves `/var/lib/budget/` → `/var/lib/life-dashboard/` (the SQLite database,
   with its already-recorded migrations, moves intact — nothing is re-run or
   wiped).
3. Re-owns the migrated data to the new `life-dashboard` service user.
4. Removes the rebuildable `/opt/budget` and `/etc/budget` (releases are rebuilt;
   the env file and deploy key are re-rendered from vault).

Every step guards on the legacy artefacts still being present, so on an
already-migrated or fresh host the task is a no-op. The old `budget` system
account is intentionally left in place (removing a system user is destructive and
it owns nothing after the handover); drop it by hand if you want a clean slate.
Once every host has migrated, set `life_dashboard_migrate_legacy: false`.

On-host layout
--------------

    /opt/life-dashboard/releases/<ts>/   built release (checkout + npm ci + build)
    /opt/life-dashboard/current ->        symlink to the active release
    /var/lib/life-dashboard/app.db        SQLite — persists across redeploys
    /var/lib/life-dashboard/images/       uploaded images — persist across redeploys
    /etc/life-dashboard/env               HOST, PORT, NODE_ENV, DATABASE_PATH,
                                          ORIGIN, IMAGES_DIR
    /etc/life-dashboard/deploy_key        read-only repo deploy key (0600)

Dependencies
------------

None declared in meta (the play applies `nodejs` and `nginx` alongside this
role). Functionally requires `nodejs` to have run first.

Example Playbook
----------------

    - name: Deploy the Life-Management-Dashboard service
      hosts: life_dashboard
      become: true
      gather_facts: true
      roles:
        - common
        - nodejs
        - life_dashboard
        - nginx

License
-------

MIT
