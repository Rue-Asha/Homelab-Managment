# Tailscale Subnet Router

Remote access into the flat `192.168.0.0/24` LAN from anywhere, over Tailscale's
outbound-only WireGuard tunnel — **no inbound ports are opened** on the home
router. A single dedicated LXC (`tailscale01`) advertises the LAN route into the
tailnet; remote Tailscale devices reach `192.168.0.x` directly.

```
  Laptop / phone (anywhere)                     Home LAN 192.168.0.0/24
  ┌──────────────────┐   WireGuard (no        ┌───────────────────────────┐
  │ Tailscale client │═══ port-forward) ═════▶│ tailscale01  (subnet      │
  │ "use subnet      │                        │   router, ip_forward=1)   │
  │  routes" enabled │                        │        │                  │
  └──────────────────┘                        │        ▼                  │
                                              │  pihole01 / partygames01  │
                                              │  / proxmox UI :8006 …     │
                                              └───────────────────────────┘
```

## Scope

- **IP-only** access (`--accept-dns=false`). No DNS / MagicDNS / Pi-hole over the
  VPN. Reach hosts by IP.
- Subnet router only — **not** an exit node (remote traffic is not full-tunnelled
  through home).
- Single flat `/24`; one advertised route.

## Prerequisites (Tailscale admin console — one time)

1. A Tailscale account / tailnet. The free **Personal** plan covers subnet
   routers, up to 6 users and unlimited devices — no paid plan required.
2. Generate a **pre-auth key** (Settings → Keys). Put it in the host vault,
   replacing the placeholder:
   ```bash
   ansible-vault edit inventory/host_vars/tailscale01/vault.yml
   # set: tailscale_authkey: tskey-auth-...
   ```

## Deploy

Pick a free LAN IP for `tailscale01` in `inventory/hosts` (default
`192.168.0.230`; the CTID is derived from the last octet → CT `230`).

```bash
# 1. Provision the LXC (creates CT, bootstraps SSH, adds TUN passthrough + reboot)
ansible-playbook playbooks/01_PROVISIONING/lxc_proxmox.yml --limit tailscale01

# 2. Install Tailscale and bring the subnet router up
ansible-playbook playbooks/03_SERVICES/tailscale.yml --limit tailscale01
```

## Complete in the admin console (manual — Ansible cannot do these)

3. **Approve the advertised route.** Machines → `tailscale01` → Route settings →
   approve `192.168.0.0/24`. Advertising alone does not activate it.
   - *Optional automation:* add an ACL `autoApprovers` entry with a device tag to
     skip this click on future rebuilds.
4. **Disable key expiry** for `tailscale01` (Machines → `⋯` → Disable key
   expiry). Otherwise the node key lapses (~6 months) and the tunnel silently
   drops — while you are remote.

## Use it (remote device)

- Install Tailscale and sign into the same tailnet.
- Ensure **"use subnet routes"** is enabled (on by default on desktop; a toggle
  on iOS/Android).
- Verify: reach `http://192.168.0.22:8006` (Proxmox UI) and `192.168.0.224`
  (party games).

## Operations

- **Verify on the box:**
  ```bash
  tailscale status          # connected; shows advertised route
  ls -l /dev/net/tun        # device present (TUN passthrough OK)
  sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding   # both = 1
  ```
- **Rotate the key:** generate a new pre-auth key, `ansible-vault edit` the
  vault, re-run `03_SERVICES/tailscale.yml`. The `tailscale up` step re-runs when
  the node is not `Running`; to force re-auth, run `tailscale up` manually on the
  host or `tailscale logout` first.
- **Rollback:** stop/destroy the `tailscale01` LXC and delete the node from the
  tailnet. No other host is affected.

## How it maps to the repo

| Concern | Where |
|---|---|
| Host + sizing + routes + TUN flag | `inventory/hosts`, `host_vars/tailscale01/{vars,vault}.yml` |
| `/dev/net/tun` passthrough (host-level) | `roles/proxmox_lxc_tun` (in `01_PROVISIONING`) |
| Install + forwarding + `tailscale up` | `roles/tailscale` (`install`/`configure`/`service`) |
| Service playbook | `playbooks/03_SERVICES/tailscale.yml` |
