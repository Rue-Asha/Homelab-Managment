## Why

I want to self-host a personal life-management dashboard on the Proxmox homelab, reachable
only from the LAN or over VPN (financial data must never touch the public
internet). The party-games service already proved out the "slim web service in
its own LXC" pattern (app-per-LXC, build-on-host, Ansible-driven, `systemd` +
nginx). Reusing that exact pattern gives the life-management dashboard the same atomic
deploys, instant rollback, and zero-container overhead with almost no new
infrastructure to design.

## What Changes

- Add a new **`life-dashboard01` LXC** guest (Debian) under the existing
  `lxc_container_proxmox` inventory group, provisioned by the existing
  `01_PROVISIONING/lxc_proxmox.yml` playbook.
- Add a new **`life-dashboard` service role** that mirrors `roles/partygames`:
  build-on-host release management (checkout pinned git version → `npm ci` →
  build → prune), atomic `current` symlink go-live, a persistent SQLite database
  under `/var/lib/life-dashboard/`, an env file, and a `systemd` unit.
- Add a new **`03_SERVICES/life-dashboard.yml` playbook** applying
  `common → nodejs → life-dashboard → nginx` (identical role stack to party-games).
- Reuse the existing **`nodejs`** and **`nginx`** roles unchanged; enable the
  nginx reverse proxy (`:80` → `127.0.0.1:<life_dashboard_port>`) via `life-dashboard01`
  host_vars.
- Add **`inventory/host_vars/life-dashboard01/`** (`vars.yml` + vaulted `vault.yml`) with
  the app repo URL, pinned version, deploy key, and LXC sizing.
- Register `life-dashboard01` in `inventory/hosts` under the `lxc_container_proxmox`
  children and add a `[life_dashboard]` group.
- The dashboard **application itself lives in its own separate repo** (SvelteKit +
  adapter-node + SQLite), referenced by URL + a pinned git tag — the equivalent
  of an image tag. Writing that app is out of scope for this change.

## Capabilities

### New Capabilities
- `life-dashboard-webservice`: Self-hosted dashboard web service deployed app-per-LXC —
  provisioning of the `life-dashboard01` container, build-on-host release/rollback
  lifecycle, persistent SQLite storage, `systemd` supervision, and an nginx
  reverse proxy in front, reachable only over LAN/VPN.

### Modified Capabilities
<!-- None. This change adds a new service; it does not alter the requirements of
     any existing capability. The nodejs and nginx roles are reused as-is. -->

## Impact

- **New role:** `roles/life-dashboard/` (structurally a copy of `roles/partygames/`).
- **New playbook:** `playbooks/03_SERVICES/life-dashboard.yml`.
- **New inventory:** `inventory/host_vars/life-dashboard01/{vars.yml,vault.yml}`; edits to
  `inventory/hosts`.
- **Reused, unchanged:** `roles/common`, `roles/nodejs`, `roles/nginx`,
  `roles/proxmox_lxc`, `roles/proxmox_lxc_bootstrap`.
- **New Proxmox guest:** one LXC (`life-dashboard01`, ~2 cores / 1 GB / 10 GB), a new
  static LAN IP and CTID.
- **Secrets:** a read-only deploy key for the private app repo, appended to the
  vault as the last entry (per repo convention).
- **External dependency:** the separate dashboard app repo must exist (at least a
  buildable skeleton) before the role can be applied end to end.
- **No public exposure:** no Let's Encrypt / inbound :443; plain HTTP on the
  trusted network, self-signed TLS deferred.
