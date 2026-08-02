## Context

The homelab already runs one slim self-made web service (party-games) using a
settled delivery model documented in
`docs/party-games-webservice-architecture.md`: **app-per-LXC, build-on-host,
Ansible-driven, no container images**. `systemd` supervises the Node process;
nginx fronts it as a plain reverse proxy; SQLite persists data; releases are
timestamped directories with an atomic `current` symlink swap for go-live and
rollback.

The life-management dashboard is the second service to follow this pattern. Its runtime
shape is effectively identical to party-games: a SvelteKit (`adapter-node`) app
with a SQLite database, reachable only over LAN/VPN. The `roles/partygames`
role is already almost entirely generic (parameterised paths, ports, user, repo
URL, build/migrate commands), so this change is mostly a faithful copy with a new
variable prefix plus new inventory and a new play.

The one domain difference worth flagging: dashboard data is **sensitive
financial data**. That raises the value of eventual application-level auth and
TLS — but both are properties of the app repo and a later hardening pass, not of
this deployment change.

## Goals / Non-Goals

**Goals:**

- Stand up a `life-dashboard01` LXC and deploy a self-made SvelteKit dashboard app into it
  using the exact party-games delivery model.
- Reuse `common`, `nodejs`, and `nginx` roles unchanged; enable the proxy via
  host_vars.
- Give the service atomic deploys, instant rollback, persistent SQLite, and
  `systemd` supervision.
- Keep the app source in its own separate repo, referenced by URL + pinned
  version.

**Non-Goals:**

- Writing the dashboard application itself (separate repo; only a buildable
  skeleton is a prerequisite for an end-to-end run).
- Application-level authentication / user accounts (an app concern).
- Public-internet exposure, Let's Encrypt, or inbound :443.
- Multi-container topology or independent backend/proxy scaling.
- Refactoring `roles/partygames` into a shared generic role (see Decisions).

## Decisions

### Decision: New dedicated `life-dashboard` role, copied from `partygames`

Create `roles/life-dashboard/` as a structural copy of `roles/partygames/` with the
variable prefix renamed `partygames_*` → `life_dashboard_*` and service identity/paths
(`/opt/life-dashboard`, `/var/lib/life-dashboard`, `/etc/life-dashboard`, `life-dashboard.service`) adjusted.
Same task split (`user`, `directories`, `deploy_key`, `checkout`, `build`,
`migrate`, `config`, `release`, `service`, `prune`), same `deploy` tags, same
handler, same env + unit templates.

**Alternatives considered:**

- *Generalise into a shared `node_webservice` role parameterised by service
  name.* This is the DRY-correct end state — the two roles will be ~95%
  identical. Rejected **for now** because: (1) the repo's stated convention is a
  service-per-role, and party-games is the only proven consumer; (2) extracting a
  reusable role is a separate refactor that should not ride along with standing
  up a new service (it would also churn the working party-games deploy). Captured
  as an open question / future change instead — with two real consumers the
  extraction becomes well-motivated and low-risk.
- *Reuse the `partygames` role directly with different vars.* Rejected: the role
  name, service name, and on-host paths are baked into defaults and templates;
  running it for a second service would collide on identity and be confusing.

### Decision: Same stack — SvelteKit + adapter-node + SQLite + Node built-in `node:sqlite`

Mirror party-games' runtime exactly so the reused `nodejs` role and the copied
build/service tasks apply without change. Node's built-in `node:sqlite`
(Node ≥ 22, already what the `nodejs` role installs) keeps the LXC free of a C
build toolchain.

**Alternatives considered:** a different DB (Postgres) or a non-Node stack —
rejected as needless divergence from a proven, single-user pattern.

### Decision: Reuse `nodejs` and `nginx` roles unchanged; enable proxy via host_vars

`playbooks/03_SERVICES/life-dashboard.yml` applies `common → nodejs → life-dashboard → nginx`,
matching party-games. `host_vars/life-dashboard01/vars.yml` sets
`nginx_reverse_proxy_enabled: true`, `nginx_backend_port: "{{ life_dashboard_port }}"`,
and `nginx_service_description`. Host-level concerns (runtime install, proxy)
stay out of the service role, per repo convention.

### Decision: New inventory identity for `life-dashboard01`

Add a `[life_dashboard]` group to `inventory/hosts` as a child of
`lxc_container_proxmox`, with `life-dashboard01` on static LAN IP `192.168.0.226`
(confirm free at apply time) and a new unused CTID. Add `host_vars/life-dashboard01/vars.yml` (LXC sizing + app
repo URL + pinned version + nginx overrides) and a vaulted `vault.yml` holding
the read-only deploy key, appended as the last vault entry.

### Decision: Version-marker idempotency (inherited)

Keep party-games' `.deployed_version` marker mechanism: a redeploy only happens
when the requested `life_dashboard_version` differs from the recorded live version, so
re-running the play is a cheap no-op. `--tags deploy` runs just the
checkout→build→migrate→activate→prune path.

## Risks / Trade-offs

- **Two near-identical roles drift over time** → Accept short-term duplication;
  file a follow-up to extract a shared `node_webservice` role now that a second
  consumer justifies it. Until then, port any party-games role bugfix to both.
- **App repo does not yet exist / is not buildable** → The role cannot complete
  an end-to-end run. Mitigation: land the role + inventory first; require at
  least a SvelteKit skeleton (buildable, with a `db:migrate` or disabled
  migration command) before the first real deploy. `life_dashboard_migrate_command` can
  be set to `""` to skip migrations initially.
- **Sensitive financial data on plain HTTP** → Traffic is LAN/VPN-only and the
  backend binds to loopback, but there is no transport encryption or app auth
  yet. Mitigation: treat self-signed TLS (`nginx_tls_enabled`) and app-level auth
  as a fast follow; document the gap.
- **IP / CTID collision with an existing guest** → A wrong static IP or reused
  CTID breaks provisioning. Mitigation: verify the chosen IP and CTID are free on
  the Proxmox node before applying `01_PROVISIONING`.
- **Deploy key leakage** → A committed unencrypted key would expose the private
  app repo. Mitigation: key lives only in the vault, installed `0600`, `no_log`
  on the task (inherited from party-games).

## Migration Plan

1. Land role + playbook + inventory (no host impact yet).
2. Ensure the dashboard app repo exists and builds (at least a skeleton).
3. Provision: run `01_PROVISIONING/lxc_proxmox.yml` limited to `life-dashboard01`, then
   base-config via `common`.
4. Deploy: run `03_SERVICES/life-dashboard.yml` (optionally `-e life_dashboard_version=<tag>`).
5. Verify: service reachable through nginx on `:80` over LAN/VPN; DB file present
   under `/var/lib/life-dashboard/`.
6. **Rollback:** repoint `current` at the prior release (or re-run at the old
   version). The SQLite file is untouched by redeploys.

## Open Questions

- **Extract a shared `node_webservice` role?** Recommended as a separate
  follow-up change once this lands, since there are now two consumers. Not part
  of this change.
- **Confirm the static IP and CTID** for `life-dashboard01` against the live Proxmox node
  at apply time.
- **Enable self-signed TLS and app-level auth now or later?** Proposed: later
  hardening pass, given LAN/VPN-only reach and loopback backend binding.
