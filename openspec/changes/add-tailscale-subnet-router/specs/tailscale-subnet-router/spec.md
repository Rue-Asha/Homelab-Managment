## ADDED Requirements

### Requirement: Dedicated subnet-router LXC

The system SHALL provision a dedicated LXC container (`tailscale01`) on
`proxmox1` whose sole purpose is to act as a Tailscale subnet router. The
container SHALL be defined in inventory under a `[tailscale]` group nested in
`lxc_container_proxmox`, sized minimally, and SHALL NOT co-host any other
service.

#### Scenario: Container is created and reachable on the LAN

- **WHEN** the provisioning playbook runs against `tailscale01`
- **THEN** an unprivileged LXC exists on `proxmox1` with a static
  `192.168.0.x/24` address on `vmbr0` and is reachable over SSH by the `ansible`
  user

#### Scenario: Container hosts nothing else

- **WHEN** the inventory is inspected
- **THEN** `tailscale01` belongs only to the `tailscale` group and runs no other
  homelab service role

### Requirement: TUN device availability

The container SHALL have access to `/dev/net/tun`. Because an unprivileged
Proxmox LXC has no TUN device by default, provisioning SHALL enable TUN
passthrough at the host level by adding the required entries to the container's
Proxmox config on `proxmox1`. This host-level step SHALL NOT live in the
`tailscale` application role.

#### Scenario: TUN passthrough is configured on the host

- **WHEN** provisioning completes
- **THEN** the container's `/etc/pve/lxc/<ctid>.conf` on `proxmox1` contains a
  cgroup device-allow entry and a bind mount for `/dev/net/tun`

#### Scenario: Tailscale can open the tunnel device

- **WHEN** Tailscale starts inside the container
- **THEN** it successfully opens `/dev/net/tun` and does not fall back to
  userspace networking due to a missing device

### Requirement: IP forwarding enabled

The container SHALL have IPv4 and IPv6 forwarding enabled persistently so it can
route traffic from the tailnet into the LAN.

#### Scenario: Forwarding sysctls are set and persistent

- **WHEN** the `tailscale` role has converged the host
- **THEN** `net.ipv4.ip_forward` and `net.ipv6.conf.all.forwarding` are `1` and
  survive a reboot

### Requirement: Tailscale installation

The system SHALL install Tailscale from its official APT repository via the
`ansible.builtin.apt` module, passing packages as a single list.

#### Scenario: Tailscale package present

- **WHEN** the `tailscale` role runs on `tailscale01`
- **THEN** the `tailscale` package is installed and the `tailscaled` service is
  enabled and running

### Requirement: Unattended tailnet join and route advertisement

The container SHALL join the tailnet non-interactively using a pre-auth key
sourced from Ansible Vault, and SHALL advertise the `192.168.0.0/24` route.
Remote access SHALL be by IP only: the node SHALL accept no DNS from the tailnet
(`--accept-dns=false`). The pre-auth key SHALL NOT be committed in plaintext.

#### Scenario: Node joins and advertises the subnet

- **WHEN** the `tailscale` role brings the node up
- **THEN** the node authenticates with the vaulted pre-auth key and advertises
  `192.168.0.0/24` with DNS acceptance disabled

#### Scenario: Secret stays encrypted

- **WHEN** the repository is inspected
- **THEN** the pre-auth key exists only inside an Ansible Vault file and never in
  plaintext

### Requirement: No inbound exposure

The design SHALL require no router port forwarding and no inbound firewall
openings. Connectivity SHALL rely solely on Tailscale's outbound-only tunnel.

#### Scenario: Remote device reaches the LAN with no ports forwarded

- **WHEN** a remote Tailscale device with subnet routes enabled connects, after
  the advertised route is approved in the Tailscale admin console
- **THEN** it can reach `192.168.0.x` hosts (e.g. `partygames01`, `pihole01`,
  the Proxmox UI) without any inbound port being opened on the home router

### Requirement: Documented manual operational steps

Because they occur in the Tailscale admin console outside Ansible's reach, the
change SHALL document the manual steps required to complete and sustain the
subnet router: approving the advertised route and disabling key expiry on the
`tailscale01` node.

#### Scenario: Operator has the runbook

- **WHEN** an operator follows the change documentation
- **THEN** they are instructed to approve the `192.168.0.0/24` route and to
  disable key expiry for the `tailscale01` node so the tunnel does not lapse
