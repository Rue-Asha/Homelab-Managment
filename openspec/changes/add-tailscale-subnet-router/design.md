## Context

The homelab is a flat `192.168.0.0/24` LAN behind a home router with no inbound
ports open. Guests (`pihole01`, `retropie01`, `partygames01`, the Proxmox UI at
`.22:8006`) are reachable only from inside the LAN. The goal is remote reach into
that `/24` without exposing anything to the public internet.

Tailscale's **subnet router** feature fits exactly: one node inside the LAN joins
a WireGuard-based tailnet and advertises the LAN route; remote tailnet devices
then reach `192.168.0.x` directly. The tunnel is outbound-only (UDP 41641, DERP
relay fallback), so no port forwarding is required.

Constraints from project conventions (`.claude/CLAUDE.md`):
- App-per-LXC; `systemd` supervises the process.
- Host-level concerns (firewall, kernel/device config) must not live in a
  service/app role.
- Roles split tasks per function; `tasks/main.yml` is an import-only hub.
- Prefer distro package modules; pass package lists as a single list.
- Vault secrets appended as the last entry; never commit plaintext secrets.

## Goals / Non-Goals

**Goals:**
- Remote IP-level reach into `192.168.0.0/24` from any Tailscale device.
- Zero inbound ports; nothing exposed to the public internet.
- Repeatable, idempotent Ansible convergence following repo conventions.
- Instant rollback (destroy one LXC; no other host touched).

**Non-Goals:**
- DNS over the VPN / MagicDNS / Pi-hole-as-nameserver (`--accept-dns=false`).
- Exit-node behavior (routing *all* remote traffic through home).
- Multi-subnet / VLAN routing — the LAN is a single flat `/24`.
- Automating Tailscale admin-console actions (route approval, key expiry).

## Decisions

### D1: Dedicated `tailscale01` LXC (not on `pihole01` or the host)
A single-purpose LXC keeps concerns isolated and rollback trivial, and matches
the app-per-LXC model. Sized minimally (≈1 core / 512 MB / 4 GB).
- *Alternatives:* Co-host on `pihole01` (rejected — couples DNS and VPN, and
  DNS-over-VPN is out of scope); run on the `proxmox1` host (rejected — puts
  Tailscale on the hypervisor; unnecessary for a flat `/24`).

### D2: Unprivileged LXC + host-level TUN passthrough
Keep the container unprivileged for security and add `/dev/net/tun` via the
Proxmox CT config on the host:
```
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```
This edit targets `/etc/pve/lxc/<ctid>.conf` on `proxmox1`, delegated to the
host — a **provisioning** step, deliberately kept out of `roles/tailscale`.
- *Alternatives:* Privileged LXC (rejected — weaker isolation for the one box
  that is the door into the whole LAN).

### D3: `roles/tailscale` owns install + forwarding + join only
Role task split: `install.yml` (APT repo + `tailscale` package), `configure.yml`
(persistent `ip_forward` / IPv6 forwarding sysctls), `service.yml` (`tailscale up`
with vaulted authkey, `--advertise-routes=192.168.0.0/24 --accept-dns=false`);
`main.yml` imports them in order. `tailscaled` is supervised by `systemd`.
Kernel forwarding sits at the boundary between host and app concern; it is placed
in the role because it is intrinsic to *this* node's routing function and is a
guest-internal sysctl, not host config.

### D4: Unattended join via vaulted pre-auth key
Use a Tailscale pre-auth key from the admin console, stored in
`host_vars/tailscale01/vault.yml` (appended last, per convention), so
convergence is non-interactive and idempotent. The role SHALL guard `tailscale
up` so re-runs don't thrash an already-connected node.
- *Alternatives:* Interactive `tailscale up` login (rejected — not automatable).

### D5: Reuse existing provisioning; add one host task
Container creation reuses `01_PROVISIONING/lxc_proxmox.yml`. The only new
provisioning work is the TUN passthrough task (delegated to `proxmox1`), which
must run before the container starts Tailscale.

## Risks / Trade-offs

- **Route approval is manual** → Document it; optionally add a Tailscale ACL
  `autoApprovers` entry (with a tag) later to remove the click.
- **Node key expiry (~6 months) silently drops the only door** → Document
  disabling key expiry on `tailscale01` in the admin console as a required step.
- **TUN passthrough misconfigured → Tailscale falls back to userspace / fails**
  → Spec scenario verifies `/dev/net/tun` opens; passthrough runs at provision
  time before service bring-up.
- **Single point of entry** → Acceptable for a homelab; if the LXC is down there
  is no remote access. Mitigated by `onboot: true` and `systemd` restart.
- **Pre-auth key leakage** → Vault-only storage; keys can be scoped/ephemeral and
  rotated from the console.

## Migration Plan

1. Create Tailscale account/tailnet; generate a pre-auth key.
2. Add inventory (`[tailscale]` group, `host_vars/tailscale01/{vars,vault}.yml`).
3. Provision: run `01_PROVISIONING/lxc_proxmox.yml` for `tailscale01`; apply the
   TUN passthrough host task; base-configure the host.
4. Run `03_SERVICES/tailscale.yml` to install and bring up the subnet router.
5. In the admin console: **approve** the `192.168.0.0/24` route and **disable key
   expiry** for `tailscale01`.
6. On a remote client, enable "use subnet routes"; verify reach to
   `192.168.0.224` and the Proxmox UI.

**Rollback:** stop/destroy the `tailscale01` LXC and remove the node from the
tailnet; no other host is affected.

## Open Questions

- Automate route approval via ACL `autoApprovers` + a device tag now, or accept
  the one-time manual click? (Leaning: manual now, ACL later.)
- Should `tailscale01` also be an **exit node** eventually (full-tunnel remote),
  or stay subnet-router-only? (Currently out of scope.)
