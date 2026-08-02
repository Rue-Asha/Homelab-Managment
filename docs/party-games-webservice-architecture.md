# Party Games Web Service — Architecture Decisions

> Status: design. Captures the design discussion for the self-hosted party-games
> web service and the roles that deploy it. Delivery model decided 2026-06-18
> (see "Delivery & deployment"). Reference for future work.

## Overarching goal

Host self-made party games as a web service, reachable **from within the homelab
or over VPN** (never the public internet). Runs on a Proxmox **LXC**
(`partygames01`).

## Usage model (the key constraint)

- **Exactly one browser connects** — the games are played on a single screen, not
  one-device-per-player. There is no multi-client real-time sync.
- Consequence: **no WebSockets, no Socket.IO, no lobby/room logic.** Those exist to
  sync multiple clients; with one client there is nothing to sync.
- Game logic and visuals run **in the browser**.

## Why there is still a backend

A backend is needed purely for **persistence**: tracking prompts, scores, and
similar state that must survive refreshes. Not for real-time, not for proxying
multiple clients.

## Chosen stack

| Layer | Choice | Rationale |
|---|---|---|
| App framework | **SvelteKit** (`adapter-node`) | Full-stack: UI + server endpoints + DB access in one app/repo/process. One language (TS) end to end. Best developer velocity for a solo dev. |
| UI / animation | **Svelte built-in transitions** for DOM/UI; **PixiJS** (or plain `<canvas>`/CSS sprites) for animated sprite sequences | Mix of DOM-based UI and occasional sprite animations (e.g. animated explanations). No full game engine needed. |
| Persistence | **SQLite** (via Drizzle ORM, or raw better-sqlite3) | File-based, zero admin, trivial to back up (copy the file), plenty for a single user. Can migrate to Postgres later if ever needed. |
| Runtime | **Node.js** (TypeScript) | Runs the SvelteKit `adapter-node` server process. |
| Web server | **nginx** as a **plain reverse proxy** | Terminates the network on :80, forwards to the Node process on localhost. No WebSocket upgrade headers required. |

## Topology

Backend + nginx live on the **same LXC** (simplest; backend never exposed
directly; no network hop). Split only if independent scaling is ever needed — not
expected for a single-user homelab.

```
[browser] --LAN / VPN--> nginx (:80, LXC)
                           └── proxy_pass 127.0.0.1:<backend_port>
                                 └── SvelteKit (adapter-node, Node process)
                                       └── SQLite (.db file)
```

## TLS

Internal/VPN-only, so **Let's Encrypt is out** (no public domain / inbound :443).
Start with **plain HTTP** (trusted network); add a **self-signed cert** later if
desired. An internal CA cert is the other option if one exists.

## Role split (kept separate, per repo convention)

- **`nginx` role** — web server / reverse proxy only (done). Service-agnostic and
  opt-in: a bare run installs nginx and keeps the stock default site; the proxy
  vhost (`:80` → `127.0.0.1:<backend_port>`, plain, no WS) turns on via
  `nginx_reverse_proxy_enabled`. Does **not** manage the firewall (host-level
  concern). TLS deferred.
- **`nodejs` role** (future, separate, reusable) — installs the Node runtime only.
- **`partygames` role** (future, separate) — service role: deploy user,
  checkout + build, release layout, the SQLite DB file, env file, and a systemd
  unit. Consumes `nodejs` + `nginx`.

## Delivery & deployment — decided 2026-06-18

**Decision: app-per-LXC, build-on-host, Ansible-driven. No container images, no
registry, no CI required to start.** An image/CI + docker-compose model was
considered and rejected for this homelab: its benefits scale with team size and
service count (both ~1 here), while Docker-in-LXC adds nesting/privilege cost. The
LXC itself is the unit; Ansible converges it into the service, and **systemd** is
the process supervisor (the role a container runtime plays elsewhere).

**Two repos:**

- `Homelab-Managment` (this repo) — configures the host.
- `partygames` (separate, to be created) — the SvelteKit app source + its build.
  Referenced from `host_vars/partygames01` by repo URL + a **pinned version**
  (git tag/commit) — the equivalent of an image tag. A private repo needs a
  read-only deploy key on the host.

**Roles applied by `playbooks/03_SERVICES/partygames.yml` (`hosts: partygames`):**
`common` (02 base layer) → `nodejs` → `partygames` → `nginx`. `partygames01`
host_vars enable the proxy (`nginx_reverse_proxy_enabled: true`,
`nginx_backend_port: 3000`, `nginx_service_description`).

**On-host layout:**

```
/opt/partygames/releases/<ts>/   built release (git checkout + npm ci + build)
/opt/partygames/current ->        symlink to the active release
/var/lib/partygames/app.db        SQLite — persists across redeploys
/etc/partygames/env               PORT=3000, NODE_ENV=production, DB path
```

**Deploy flow:** run the playbook (optionally `-e version=<tag>`) → the role
checks out the pinned ref into a fresh `releases/<ts>`, runs `npm ci &&
npm run build`, applies DB migrations, flips `current`, restarts
`partygames.service`. **Rollback** = repoint `current` at the previous release
(or re-run at the old tag).

**SQLite:** prefer Node's built-in `node:sqlite` (or `better-sqlite3` prebuilds)
so the LXC needs no C build toolchain. The DB file lives at
`/var/lib/partygames/app.db`, owned by the service user, never wiped by a deploy.

**Artifact:** none. Build-on-host carries source and builds on the box, so there
is no prebuilt artifact. Graduate to a shipped tarball only if the host must stay
toolchain-free or builds need CI — only the checkout/build steps change.

**Prerequisite:** the `partygames` app repo (SvelteKit + adapter-node + SQLite,
even a skeleton) must exist before the `nodejs`/`partygames` roles can be built
and tested.

**Implementation checklist:** `docs/party-games-implementation-plan.md`.

## Decisions explicitly rejected

- **Socket.IO / WebSockets** — single client, nothing to sync.
- **Separate backend framework (Express/FastAPI/Go)** — SvelteKit is already
  full-stack; a second backend would add a process and a language for no gain.
- **Postgres** — overkill for single-user; SQLite is sufficient.
- **Let's Encrypt** — not reachable from the public internet.
- **Backend on a separate VM** — no scaling need; co-locating is simpler.
- **Container images + registry + CI/CD (Docker/Podman)** — benefits scale with
  team size and service count (both ~1); Docker-in-LXC adds nesting/privilege
  cost. App-per-LXC + Ansible reuses the existing tooling. Revisit only for a
  many-service or image-only-distributed workload.
