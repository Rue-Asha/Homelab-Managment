## Why

The homelab is only reachable from inside the `192.168.0.0/24` LAN. Reaching it
from outside today would mean forwarding ports on the router — exposing services
to the public internet. A Tailscale subnet router gives full remote reach into
the flat `/24` over an outbound-only WireGuard tunnel, with **zero inbound ports
open**, so nothing is exposed.

## What Changes

- Add a new dedicated, tiny LXC (`tailscale01`) on `proxmox1` whose sole job is
  to be a Tailscale **subnet router** advertising `192.168.0.0/24`.
- Provisioning gains a **host-level** step: enable `/dev/net/tun` passthrough for
  the container's config on `proxmox1` (an unprivileged LXC has no TUN device by
  default, which Tailscale requires).
- Add a new `roles/tailscale` role that installs Tailscale, enables IPv4/IPv6
  forwarding inside the guest, and brings the node up with a vaulted pre-auth key
  plus `--advertise-routes=192.168.0.0/24 --accept-dns=false`.
- Add inventory wiring: a `[tailscale]` group under `lxc_container_proxmox`, and
  `host_vars/tailscale01/{vars,vault}.yml` (sizing, CTID, routes, auth key).
- Add a `03_SERVICES/tailscale.yml` service playbook.
- DNS-over-VPN is explicitly **out of scope** — remote access is by IP only
  (`--accept-dns=false`).
- Two operational steps remain **manual / out-of-band** in the Tailscale admin
  console: approving the advertised route and disabling key expiry on the node.

## Capabilities

### New Capabilities
- `tailscale-subnet-router`: A dedicated LXC that joins the tailnet and routes
  traffic from remote Tailscale devices into the local `192.168.0.0/24`, giving
  outbound-only remote access to the homelab with no exposed inbound ports.

### Modified Capabilities
<!-- None — no existing spec-level behavior changes. -->

## Impact

- **New host:** `tailscale01` LXC (≈1 core / 512 MB / 4 GB) on `proxmox1`.
- **Provisioning:** new host-level task to edit the CT config on `proxmox1`
  (`lxc.cgroup2.devices.allow` + `lxc.mount.entry` for `/dev/net/tun`). Host
  concern — stays out of the app role, per project convention.
- **New role:** `roles/tailscale` (install / configure / service), `main.yml` as
  an import-only hub.
- **Inventory:** `inventory/hosts`, new `host_vars/tailscale01/`.
- **New dependency:** Tailscale apt repository + `tailscale` package; a Tailscale
  account/tailnet and a pre-auth key (stored in vault as the last entry).
- **Playbook:** `playbooks/03_SERVICES/tailscale.yml`; reuses existing
  `01_PROVISIONING/lxc_proxmox.yml` for container creation.
- **No router/firewall changes** — no port forwarding; the tunnel is
  outbound-only.
