# Life-Management-Dashboard Web Service

Self-hosted single-user personal dashboard ("Zentrale" —
[`Life-Managment-Dashboard`](https://github.com/Rue-Asha/Life-Managment-Dashboard)):
five modules — Overview, Tasks, Uni, Projects, Notes. Reachable **only
from the homelab LAN or over VPN** (it holds sensitive personal data, which
never touches the public internet). Runs on a Proxmox **LXC**
(`life-dashboard01`).

App `v2.0.0` ("SISTEMA") is a breaking redesign down to those five modules:
finance, curriculum, review, search and the Proton-ICS agenda lost their UI —
their tables stay in `app.db`, so no data is lost, but `PROTON_ICS_URL` is no
longer read. The same release adds `IMAGES_DIR` for uploaded images. `v2.1.0`
turns the note body into a block editor (headings, to-do lists, tables), and
`v2.2.0` switches the whole UI to English.

## History

The service began life as a standalone **Budgeting-Web-App** deployed under a
`budget` identity. The dashboard absorbed that app (same env contract, same
SQLite database), so the deployment was refactored `budget` → `life-dashboard`:
the role, variables (`life_dashboard_*`), host (`life-dashboard01`), on-host
paths, systemd unit, and service user were all renamed. The first deploy of the
renamed role migrates the old on-host layout in place (see
[ansible/roles/life_dashboard](../ansible/roles/life_dashboard/README.md#legacy-migration)); the
persistent database — with its already-recorded `budget` migrations `0001`–`0005`
— moves intact, and newer modules add date-prefixed migrations.

## Delivery model

Identical to the party-games service — **app-per-LXC, build-on-host,
Ansible-driven, `systemd` + nginx**. The full rationale (why no container
images, why SQLite, why a plain reverse proxy, release/rollback mechanics) lives
in **[`party-games-webservice-architecture.md`](party-games-webservice-architecture.md)**
and is not repeated here.

## Stack

SvelteKit (`adapter-node`) + SQLite (Node built-in `node:sqlite`, Node ≥ 22),
fronted by nginx as a plain reverse proxy on `:80`. The app lives in its **own
repo**, referenced from `host_vars/life-dashboard01/vars.yml` by URL + a pinned
git version (the "image tag").

Images uploaded in the UI are plain files under `IMAGES_DIR`
(`/var/lib/life-dashboard/images`), not DB rows; they are `PUT` through the
proxy, so `nginx_client_max_body_size` on this host is raised above the app's
own 15 MB cap.

## Host facts

| Item | Value |
|---|---|
| LXC host | `life-dashboard01` |
| LAN IP | `192.168.0.223` |
| CTID | `223` (derived from the IP's last octet) |
| Sizing | 2 cores / 1024 MB / 512 MB swap / 10 GB |
| Backend port | `127.0.0.1:3000` (`life_dashboard_port`, loopback only) |
| App repo | `life_dashboard_repo_url` in `host_vars/life-dashboard01/vars.yml` |
| Pinned version | `life_dashboard_version` (immutable tag / commit) |

## Roles applied

`playbooks/03_SERVICES/life-dashboard.yml` (`hosts: life_dashboard`) applies:
`common` → `nodejs` → `life-dashboard` → `nginx`. The `life-dashboard01`
host_vars enable the proxy (`nginx_reverse_proxy_enabled: true`,
`nginx_backend_port: "{{ life_dashboard_port }}"`, `nginx_service_description`).

## On-host layout

```
/opt/life-dashboard/releases/<ts>/   built release (git checkout + npm ci + build)
/opt/life-dashboard/current ->        symlink to the active release
/var/lib/life-dashboard/app.db        SQLite — persists across redeploys
/var/lib/life-dashboard/images/       uploaded images (IMAGES_DIR) — persist too
/etc/life-dashboard/env               HOST, PORT, NODE_ENV, DATABASE_PATH,
                                      ORIGIN, IMAGES_DIR
/etc/life-dashboard/deploy_key        read-only repo deploy key (0600)
```

## Deploy & rollback

```bash
# Deploy the pinned version (or override with -e life_dashboard_version=<tag>)
ansible-playbook playbooks/03_SERVICES/life-dashboard.yml
```

The role checks out the pinned ref into a fresh `releases/<ts>`, runs
`npm ci && npm run build`, applies DB migrations against the persistent
`app.db`, atomically flips `current`, and restarts `life-dashboard.service`.
**Rollback** = repoint `current` at the previous release (or re-run at the old
tag). The SQLite file is never touched by a redeploy.

## Deploy key

The private app repo is cloned over SSH with a read-only **deploy key**. The
private half is stored in `host_vars/life-dashboard01/vault.yml`
(`life_dashboard_deploy_key`); its **public half must be registered on the app
repo as a read-only Deploy Key** before the first deploy.

## Prerequisite

The separate Life-Management-Dashboard app repo (SvelteKit + `adapter-node` +
SQLite, honouring `npm ci && npm run build` → `build/`, and reading
`HOST`/`PORT`/`ORIGIN`/`DATABASE_PATH`/`IMAGES_DIR`) must exist and build before
an end-to-end deploy can run
(github.com/Rue-Asha/Life-Managment-Dashboard, currently pinned at `v2.3.0`).
