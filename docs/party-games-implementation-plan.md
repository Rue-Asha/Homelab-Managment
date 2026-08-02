# Party Games Service — Ansible Implementation Plan

> Actionable checklist for deploying the party-games service on the Ansible side.
> Design rationale: see `party-games-webservice-architecture.md`.
> Workflow convention: see `.claude/CLAUDE.md` → "Service delivery model".

Each implementable feature has its own `feat/*` branch, cut from `main`.

## 0. Prerequisites / unblockers (do first)

- [ ] **App repo exists** — a `partygames` repo with a buildable SvelteKit +
  `adapter-node` + SQLite skeleton. Separate repo, not this one; gating.
- [ ] **Merge `feat/nginx-role` → `main`** — the service-agnostic, opt-in nginx
  role is required by the wiring below. Expect conflicts with `#17` (overlapping
  task-split commits); merge deliberately.
- [ ] **`partygames01` provisioned + base-configured** — LXC exists
  (`proxmox_lxc` / `01_PROVISIONING/lxc_proxmox.yml`) and `common` has run on it.
  Note: there is no `02_BASE_CONFIGURATION` playbook yet (only a `.gitkeep`).

## 1. `nodejs` role — branch `feat/nodejs-role`

- [ ] Scaffold role (defaults / tasks / handlers / meta / README, SPDX headers)
- [ ] Install Node; pin a version (LTS ≥ 22 for built-in `node:sqlite`)
- [ ] `--syntax-check` + `ansible-lint`

## 2. `partygames` role — branch `feat/partygames-role`

- [ ] Scaffold role
- [ ] Service user — unprivileged `partygames`
- [ ] Directories — `/opt/partygames/{releases,current}`, `/var/lib/partygames`
  (data), `/etc/partygames` (env)
- [ ] Repo access — read-only deploy key for the (private) app repo
- [ ] Checkout the pinned version into `releases/<ts>`
- [ ] Build — `npm ci && npm run build`, then prune to prod deps
- [ ] Env file template — `PORT`, `NODE_ENV`, DB path
- [ ] DB migrations — run the app's migration command against
  `/var/lib/partygames/app.db`
- [ ] Atomic go-live — flip `current` → new release
- [ ] systemd unit — template, `daemon-reload` + enable/start; handlers
- [ ] Prune old releases — keep last N (rollback targets)
- [ ] Idempotency — build/flip only when the pinned version changes
- [ ] defaults / README / meta; `--syntax-check` + `ansible-lint`

## 3. Inventory & wiring — branch `feat/partygames-wiring`

- [ ] `inventory/host_vars/partygames01/vars.yml` — nginx overrides
  (`nginx_reverse_proxy_enabled: true`, `nginx_backend_port: 3000`,
  `nginx_service_description`) + partygames vars (`partygames_repo_url`,
  `partygames_version`, paths)
- [ ] Remove the orphaned `inventory/host_vars/nginx01/`
- [ ] `playbooks/03_SERVICES/partygames.yml` — `hosts: partygames`,
  `roles: [nodejs, partygames, nginx]`
- [ ] Retire/repurpose the orphaned `playbooks/03_SERVICES/nginx.yml`
- [ ] Vault — deploy key + any env secrets (append as the last vault entry)

## 4. Validation

- [ ] `--syntax-check` + `ansible-lint` clean across new roles/playbook
- [ ] End-to-end test deploy against `partygames01` (needs §0 done)

## Suggested order & dependencies

§0 blockers → `feat/nodejs-role` → `feat/partygames-role` →
`feat/partygames-wiring` → validate.

- `partygames` role consumes the `nodejs` role.
- wiring needs both roles **and** the nginx role merged into `main`.
