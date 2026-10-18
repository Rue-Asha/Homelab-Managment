## Why

Rue can reach the homelab services (Life-Manager, Rue's Arcade, Pi-hole UI, Proxmox UI) only from the home LAN. From the GrapheneOS phone, the E-Ink tablet or the Arch laptop on the road there is no way in. The Tailscale guest that once did this was torn down in `efa9f49`; `proxmox_lxc_tun` was kept for its return.

Appetite: two evenings.

## What Changes

- **S1** Declare `tailscale01` in `terraform/environments/homelab/hosts.auto.tfvars`: unprivileged LXC, `192.168.0.230/24`, group `tailscale`, tags incl. `terraform`, nesting on, small sizing, vmid left to Proxmox. CD's "has no 02_SERVICES playbook" warning for the created guest is expected and documented.
- **S2** New operator playbook `ansible/playbooks/01_BASE_CONFIGURATION/tailscale.yml`: play 1 runs `proxmox_lxc_tun` (enabled in `host_vars/tailscale01/vars.yml`), play 2 runs `common` + `tailscale`. Workstation-only, never run by CD.
- **S3** Restore the `tailscale` role from `efa9f49^`, adapted: official APT repo for the guest's release (trixie, not hardcoded bookworm), `tailscaled` enabled, IPv4 + IPv6 forwarding set persistently and verified, failing loudly when not writable.
- **S4** Join on a not-logged-in host with `--auth-key <prompted key> --advertise-routes=192.168.0.0/24 --advertise-tags=tag:subnet-router --accept-dns=false`, key never logged. The key comes from a hidden `vars_prompt` (overridable with `-e`), not from git. An empty key on a not-logged-in host fails before `tailscale up`; a logged-in host needs no key; changed advertise settings converge via `tailscale set` without re-auth.
- **S5** Docs carry the one-time tailnet policy snippet (`tagOwners` for `tag:subnet-router`, `autoApprovers.routes` `192.168.0.0/24`), so the route is approved without a click and the tagged node has no key expiry.
- **S6** Off-LAN tailnet clients reach `http://192.168.0.223`, `http://192.168.0.227`, `http://192.168.0.225/admin` and `https://192.168.0.22:8006` with no static route on the home router (Tailscale's default SNAT).
- **S7** A client checklist (GrapheneOS phone, E-Ink tablet, Arch laptop with `--accept-routes` off at home and on while away) states why a LAN host must not keep the /24 route.
- **S8** `docs/tailscale-subnet-router.md` matches the tree (no CT 230, `partygames01`, `03_SERVICES`, manual bootstrap, local `terraform apply`, vault key) and describes the rollout and rebuild flows; stale Tailscale references in `README.md`, `terraform/README.md`, `docs/terraform-ansible-split.md` and the `proxmox_lxc_tun` comments point to the new playbook.

## Non-Goals

- Service names / DNS (`*.home.arpa`, Pi-hole local records, Split DNS). IP-only for now; split off.
- Exit node.
- Headscale / a self-hosted control server; Tailscale SaaS is used.
- Tailnet policy, keys or approvals as code (Tailscale Terraform provider). The policy edit is a manual console step and already a roadmap item.
- Other people in the tailnet, per-device ACLs. Only Rue's three devices: default allow-all policy plus the tag.
- Automatic accept-routes toggling on the laptop (NetworkManager dispatcher); belongs in dotfiles.
- CD deploying the tailscale role on merge. The runner cannot reach the node; operator playbook like the runners.
- IPv6 subnet routes, TLS/HTTPS for the services, Tailscale on other guests or the node.
- Fixing `deploy.yml`'s `workflow_dispatch` list (pihole missing); unrelated finding.

## Done criteria

- [ ] With Wi-Fi off on the GrapheneOS phone, Life-Manager (`.223`), Rue's Arcade (`.227`), the Pi-hole admin (`.225/admin`) and the Proxmox UI (`.22:8006`) open; same from the E-Ink tablet.
- [ ] From the Arch laptop on a foreign network with `--accept-routes=true`, `ssh` to a guest works; at home with `--accept-routes=false` and `tailscale01` stopped, the laptop still reaches the node.
- [ ] The admin console shows `tailscale01` tagged `tag:subnet-router`, route approved without a click, key expiry disabled.
- [ ] A second run of the operator playbook (empty key prompt) reports `changed=0`.
- [ ] `scripts/proof.sh --all` is green and the PR's CI is green.

The first four can only be checked after merge, because only `runner01` applies Terraform and `tailscale01` does not exist before; they form the post-merge checklist. Every `manual (post-merge …)` scenario in the spec belongs to it; the verifier carries the checklist into `verification.md` for Gate 2, and Rue works through it after the merge with the post-merge runbook in `docs/tailscale-subnet-router.md`. No task in `tasks.md` waits for the merge.

## Capabilities

### New Capabilities
- `tailscale-subnet-router`: the `tailscale01` guest, the `tailscale` role and its operator playbook, the prompted pre-auth key, the tailnet policy snippet, off-LAN reachability and the client checklist.

### Modified Capabilities
<!-- none: the CD mapping, inventory handoff and proxmox_lxc_tun behave as specified today; this change only relies on them -->

## Impact

- New: `ansible/roles/tailscale/`, `ansible/playbooks/01_BASE_CONFIGURATION/tailscale.yml`, `ansible/inventory/host_vars/tailscale01/vars.yml`, `scripts/tests/tailscale.sh`.
- Changed: `terraform/environments/homelab/hosts.auto.tfvars` (one new guest; merging triggers the runner's plan → `infrastructure` approval → apply), `scripts/proof.sh` (two new sensors), `scripts/tests/deploy-targets.sh` (fixtures), docs (`docs/tailscale-subnet-router.md`, `README.md`, `terraform/README.md`, `docs/terraform-ansible-split.md`), comments in `ansible/roles/proxmox_lxc_tun/`.
- Live systems: Proxmox node (new LXC, `/etc/pve/lxc/<ctid>.conf` edit + container reboot), tailnet (policy edit, new tagged node), the three client devices.
- Deliberate deviation from the vault convention: the pre-auth key is prompted at run time and never stored.
