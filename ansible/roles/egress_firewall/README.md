# egress_firewall

Default-drop outbound firewall in nftables. A host with this role can reach:

- loopback, and replies on connections it is already part of
- DNS (TCP/UDP 53)
- SSH (TCP 22) to `egress_firewall_ssh_targets`
- `egress_firewall_public_tcp_ports` (default 80, 443) on any address outside
  `egress_firewall_private_networks`

Everything else is dropped, and `egress_firewall_blocked_targets` is dropped
before any accept rule is evaluated. Inbound traffic is not filtered.

The role owns `/etc/nftables.conf` and starts it with `flush ruleset`, so it
cannot share a host with another role that writes nftables rules. Rules only
hold while nothing unprivileged can change them: give it to hosts whose
workloads run without root.

Used by `playbooks/02_BASE_CONFIGURATION/deploy_runner.yml` to keep the deploy
runner off the Proxmox node and the rest of the LAN.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `egress_firewall_ssh_targets` | `[]` | IPv4 addresses SSH may reach |
| `egress_firewall_blocked_targets` | `[]` | IPv4 addresses always dropped |
| `egress_firewall_public_tcp_ports` | `[80, 443]` | Ports allowed to the internet (80: apt) |
| `egress_firewall_private_networks` / `6` | RFC 1918, link-local, CGNAT / ULA, link-local | Never "the internet" |
