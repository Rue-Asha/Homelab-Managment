partygames
==========

Deploys the **party-games** SvelteKit (`adapter-node`) web service onto a Proxmox
LXC using the build-on-host, app-per-LXC model (see
`docs/party-games-webservice-architecture.md`). The role checks out a **pinned
version** of the separate `partygames` app repo, builds it into a timestamped
release, applies DB migrations, flips an atomic `current` symlink, and supervises
the process with `systemd`.

This role owns the *service* concerns only. It does **not** install the Node
runtime (the `nodejs` role) or the reverse proxy (the `nginx` role) or manage the
firewall (host-level). The `03_SERVICES` play wires the three roles together.

Requirements
------------

- Debian (bookworm/trixie) LXC, base-configured by `common`.
- The `nodejs` role applied first (Node >= 22, for built-in `node:sqlite`).
- An `nginx` reverse proxy in front (`:80` -> `127.0.0.1:{{ partygames_port }}`).
- The separate **`partygames` app repo** must exist and be buildable
  (`npm ci && npm run build`, `adapter-node` output in `build/`). Until it does,
  the checkout/build/migrate steps cannot be exercised end to end.
- A read-only **deploy key** for the (private) app repo, supplied via vault.

Role Variables
--------------

| Variable | Default | Description |
|---|---|---|
| `partygames_repo_url` | `""` | Git URL of the app repo. Set in host_vars. |
| `partygames_version` | `main` | Pinned tag/branch/commit to deploy (the "image tag"). |
| `partygames_deploy_key` | `""` | Private deploy-key contents (from vault). Empty skips key install. |
| `partygames_user` / `_group` | `partygames` | Unprivileged service account. |
| `partygames_base_dir` | `/opt/partygames` | Holds `releases/` and the `current` symlink. |
| `partygames_data_dir` | `/var/lib/partygames` | Persistent data; holds `app.db`. Never wiped by a deploy. |
| `partygames_config_dir` | `/etc/partygames` | Env file and deploy key. |
| `partygames_db_path` | `…/app.db` | SQLite database file. |
| `partygames_host` | `127.0.0.1` | Bind address for the adapter-node server. Loopback keeps the backend reachable only via the nginx proxy, never directly on the LAN. |
| `partygames_port` | `3000` | Port the Node process listens on (match `nginx_backend_port`). |
| `partygames_node_env` | `production` | `NODE_ENV` for runtime/migrations. |
| `partygames_build_command` | `npm run build` | Build command run in the release dir. |
| `partygames_migrate_command` | `npm run db:migrate` | Migration command; override per app, or `""` to disable. |
| `partygames_keep_releases` | `5` | Releases to retain as rollback targets. |

How a deploy works
------------------

1. Read the live version from `current/.deployed_version`.
2. If it differs from `partygames_version`, a redeploy is needed; otherwise the
   expensive steps are skipped (idempotent).
3. Checkout the pinned ref into `releases/<timestamp>` (using the deploy key).
4. `npm ci` -> `npm run build` -> prune dev deps.
5. Run migrations against `/var/lib/partygames/app.db`.
6. Flip `current` -> the new release (atomic) and restart the service.
7. Prune all but the newest `partygames_keep_releases` releases.

**Rollback:** repoint `current` at a previous release (or re-run pinned to the
old version) and restart.

Releasing a new version
-----------------------

The app lives in its own repo and is decoupled from this host config: change app
code freely without touching the homelab repo, as long as the app keeps honoring
the build contract (`npm ci && npm run build` -> `build/`; `node build` reads
`HOST`/`PORT`/`DATABASE_PATH`; `npm run db:migrate` applies migrations; Node >=
22). The unit of release is a **pinned git ref** — the equivalent of an image tag.

Normal release loop:

    # 1. In the app repo: commit, then tag an immutable release
    git tag v0.2.0 && git push origin v0.2.0

    # 2. In this repo: point the host at the new tag
    #    inventory/host_vars/partygames01/vars.yml
    partygames_version: v0.2.0

    # 3. Deploy
    ansible-playbook playbooks/03_SERVICES/partygames.yml

The role builds the new ref into a fresh `releases/<ts>`, runs any new migrations
against the persistent `app.db`, atomically flips `current`, and restarts the
service. Persistent data in `/var/lib/partygames/` is never touched; downtime is
just the restart.

One-off without editing host_vars (handy for testing a tag):

    ansible-playbook playbooks/03_SERVICES/partygames.yml -e partygames_version=v0.2.0

**Use immutable tags or commit SHAs, and bump them each release.** Redeploy is
gated by a *string* comparison between the requested `partygames_version` and the
last-deployed one (recorded in `current/.deployed_version`). Pinning to a moving
branch (e.g. `main`) is sticky: the string never changes, so new commits are
**not** picked up. A new tag/commit is what triggers a rebuild.

On-host layout
--------------

    /opt/partygames/releases/<ts>/   built release (checkout + npm ci + build)
    /opt/partygames/current ->        symlink to the active release
    /var/lib/partygames/app.db        SQLite — persists across redeploys
    /etc/partygames/env               HOST, PORT, NODE_ENV, DATABASE_PATH
    /etc/partygames/deploy_key        read-only repo deploy key (0600)

Dependencies
------------

None declared in meta (the play applies `nodejs` and `nginx` alongside this
role). Functionally requires `nodejs` to have run first.

Example Playbook
----------------

    - name: Deploy the party-games service
      hosts: partygames
      become: true
      gather_facts: true
      roles:
        - common
        - nodejs
        - partygames
        - nginx

License
-------

MIT
