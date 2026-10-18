# Tailscale subnet router

Off-LAN access to the flat `192.168.0.0/24` LAN over Tailscale's outbound-only
WireGuard tunnel; **no inbound port is opened** on the home router. One
dedicated LXC, `tailscale01` (`192.168.0.230`), advertises the LAN route into
the tailnet. Rue's phone, tablet and laptop reach `192.168.0.x` by IP from
anywhere, with no static route on the router (Tailscale source-NATs the
traffic, so LAN hosts see it coming from `.230`).

```
  Phone / tablet / laptop (anywhere)            Home LAN 192.168.0.0/24
  ┌──────────────────┐   WireGuard (no        ┌───────────────────────────┐
  │ Tailscale client │═══ port-forward) ═════▶│ tailscale01  (subnet      │
  │ subnet routes on │                        │   router, SNAT)           │
  └──────────────────┘                        │        │                  │
                                              │        ▼                  │
                                              │  .223 .225 .227 .22:8006  │
                                              └───────────────────────────┘
```

| Piece | Where |
|---|---|
| Guest | `tailscale01` in `terraform/environments/homelab/hosts.auto.tfvars`, group `tailscale`, created by `runner01` like any guest |
| Operator playbook | `ansible/playbooks/01_BASE_CONFIGURATION/tailscale.yml`: play 1 `proxmox_lxc_tun`, play 2 `common` then `tailscale` |
| TUN passthrough | `ansible/roles/proxmox_lxc_tun`, enabled in `ansible/inventory/host_vars/tailscale01/vars.yml` |
| Install, forwarding, join | `ansible/roles/tailscale` (`install`, `configure`, `service`, `join`); defaults in `defaults/main.yml` |
| Pre-auth key | prompted at run time, never stored |
| Tailnet policy | admin console, pasted by hand once (see below) |

## Scope

- **IP-only**: `--accept-dns=false`. No MagicDNS, no Pi-hole names over the
  VPN. Reach hosts by IP.
- Subnet router only, **not** an exit node: remote traffic is not
  full-tunnelled through home.
- One flat `/24`, one advertised route, IPv4 only.
- Tailscale SaaS, free Personal plan; Rue's own devices only.

## Tailnet policy (once, by hand)

The node joins tagged `tag:subnet-router`. The policy below lets Rue own the
tag and approves the route for tagged nodes automatically, so a rebuild needs
no console click; tagged nodes have no key expiry. Applying it is a **manual
admin-console step** (Access controls), not code. Paste these two keys into the
existing policy, once:

```json
"tagOwners": {"tag:subnet-router": ["autogroup:admin"]},
"autoApprovers": {"routes": {"192.168.0.0/24": ["tag:subnet-router"]}}
```

## Roll out (first time)

1. Apply the tailnet policy above. It must exist before the node joins.
2. Merge the PR. `runner01` plans exactly one new LXC, Rue approves the
   `infrastructure` environment, `apply` creates `tailscale01`. The deploy job
   logs `deploy-targets: tailscale01 has no 02_SERVICES playbook` and stays
   green: expected, same as the runners. No `02_SERVICES` playbook targets the
   `tailscale` group, so a merge can never restart the VPN.
3. On the workstation fetch the inventory: `scripts/fetch-inventory.sh`.
4. In the admin console create a **pre-auth key** (Settings, Keys) with tag
   `tag:subnet-router`. One-off use is enough.
5. Run the operator playbook and paste the key at the hidden prompt:

   ```bash
   ansible-playbook ansible/playbooks/01_BASE_CONFIGURATION/tailscale.yml
   ```

   Play 1 adds the `/dev/net/tun` lines to the container's config on the node
   and reboots it; play 2 applies the baseline, installs Tailscale, enables
   forwarding and joins with `--advertise-routes=192.168.0.0/24
   --advertise-tags=tag:subnet-router --accept-dns=false`. The key is never
   logged.
6. Configure the clients (checklist below).

**Workstation only.** The runner's key has no access to the Proxmox node, which
play 1 needs, and a merge must never restart the VPN, so CD does not run this
playbook and `runner01` cannot.

## Rerun

Run the same command and leave the key prompt empty (Enter). On a converged
host the recap shows `changed=0` and nothing reboots. A node that is logged in
needs no key, even if stopped (`tailscale down`): the role brings it back up.
Changed `tailscale_advertise_routes` / `tailscale_accept_dns` converge in place
without re-auth. Changing the **tag** does not: it needs a fresh tagged key and
`tailscale up --force-reauth` on the node. Not logged in and an empty key fails
before `tailscale up`, with a message on how to create the key.

Pass the key non-interactively with `-e tailscale_authkey=…` only when you must;
it then lands in your shell history.

## Rebuild

A recreated `tailscale01` has a new CTID and a new node identity:

1. Merge the change; `runner01` applies it (approve `infrastructure`).
2. **Remove the stale `tailscale01` node** in the admin console first.
3. `scripts/fetch-inventory.sh`, create a fresh tagged pre-auth key.
4. Run the operator playbook and paste the key. Play 1 writes the TUN lines into
   the new `<ctid>.conf`; the route is auto-approved again by the policy.

## Clients

| Device | Setup |
|---|---|
| GrapheneOS phone | Log in to the tailnet, enable "Use Tailscale subnets" |
| E-Ink tablet | Same as the phone |
| Arch laptop | Default `tailscale set --accept-routes=false`. On the road: `tailscale set --accept-routes=true`. Back home: `tailscale set --accept-routes=false` |

**Why the laptop defaults to off:** a LAN host that accepts the `/24` route
sends its LAN traffic through the tunnel. When `tailscale01` stops, that host
loses its LAN path, node included (this happened before). With
`--accept-routes=false` at home the laptop keeps its direct LAN route no matter
what the router does.

**At home with the app on** (phone, tablet): LAN traffic hairpins through
`tailscale01` and works while it is up. When `tailscale01` is down, switch the
Tailscale app off.

Reachable from a client that accepts the route: `http://192.168.0.223`
(Life-Manager), `http://192.168.0.227` (Rue's Arcade), `http://192.168.0.225/admin`
(Pi-hole), `https://192.168.0.22:8006` (Proxmox), `ssh` to any guest. Pi-hole
sees tunnel queries from `192.168.0.230` and answers; DNS over the tunnel is not
the use case, it just works.

## Troubleshooting

- **Route shows "awaiting approval" in the console**: the tailnet policy is not
  applied, or the node joined without `tag:subnet-router`. Apply the
  [snippet](#tailnet-policy-once-by-hand); for a wrong tag see *Rerun*.
- **`/dev/net/tun` missing in the guest**: play 1 did not run, or the container
  was recreated. Rerun the operator playbook.
- **Forwarding sysctl task fails**: the unprivileged container refuses the write.
  The role fails loudly on purpose; read the assert message.
- **`tailscale up` failed in play 2**: the error from Tailscale is printed (the
  key is not). An expired or reused key is the usual cause; create a new one.
- **A client reaches nothing**: "use subnet routes" / `--accept-routes=true` is
  off on that client, or `tailscale01` is down (`pct status`, below).

On the box:

```bash
tailscale status                                          # connected, route advertised
ls -l /dev/net/tun                                        # TUN passthrough OK
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding   # both = 1
```

## Post-merge runbook

Everything live runs after the merge, in this order. Steps marked ⚠ act on the
running node or the tailnet; run them on Rue's go. Each names the scenario in
`openspec/changes/add-tailscale-subnet-router/specs/tailscale-subnet-router/spec.md`
it answers.

1. ⚠ **Paste the policy snippet** into the tailnet policy, before merging.
   *The live join is approved without a click* (the policy takes effect here).
2. ⚠ **Merge the PR.** The runner plan lists exactly one create,
   `module.lxc["tailscale01"]`; approve `infrastructure`; apply. The deploy job
   logs `deploy-targets: tailscale01 has no 02_SERVICES playbook` and stays
   green. *The runner plan shows exactly one new container*; *The first
   merge's deploy run shows the expected warning*.
3. **Fetch the inventory**: `scripts/fetch-inventory.sh`, then
   `ansible-inventory --graph`: `tailscale01` sits under `tailscale` →
   `lxc_container_proxmox` → `proxmox_guest` and has an `lxc_ctid`.
   *tailscale01 chains to proxmox_guest*.
4. **Create a pre-auth key** tagged `tag:subnet-router`.
   *Not logged in and no key fails before tailscale up* (the key is needed).
5. ⚠ **First operator run** from the workstation, key at the prompt (command
   above). Then on the box `ls -l /dev/net/tun`, both forwarding sysctls `1`,
   `tailscale status` connected; in the console the node is tagged
   `tag:subnet-router`, the route is approved without a click, key expiry is
   off. *The TUN device exists after the first run*; *Tailscale is installed
   and running on the guest*; *Forwarding is on and survives a restart*;
   *First join advertises the route and tag*; *The live join is approved
   without a click*.
6. ⚠ **Second run** with an empty prompt: `changed=0`, no reboot. *A second run
   changes nothing*; *A rerun on a host with TUN does not reboot it*; *A
   logged-in node is not re-authenticated*.
7. **Clients and Done checks**: set up per *Clients*. Phone with Wi-Fi off and
   the tablet open the four URLs; `dig @192.168.0.225 example.org` through the
   tunnel answers; the laptop on a foreign network with
   `--accept-routes=true` can `ssh` to a guest. *Services answer from an
   off-LAN client*; *The laptop reaches a guest from a foreign network*;
   *Pi-hole answers queries arriving from the router*.
8. ⚠ **Stop the router**: `pct stop <ctid>` for `tailscale01` on the node, with
   the laptop at home on `--accept-routes=false`. The laptop still reaches
   `192.168.0.22`, the LAN and other guests keep working, off-LAN access is
   gone. Then `pct start <ctid>` and `tailscale status` on the guest shows
   connected. *A stopped router only cuts off-LAN access*; *The laptop at home
   survives a stopped router*.

## Rollback

Remove the `tailscale01` entry in a PR (`runner01` destroys the LXC after the
usual approval) and delete the node in the admin console. No other guest is
affected. The policy snippet can stay.
