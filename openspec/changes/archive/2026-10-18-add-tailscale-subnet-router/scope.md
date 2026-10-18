# Scope: add-tailscale-subnet-router

Triage: feature + live — new capability (Tailscale subnet router guest, role, operator playbook), its rollout acts on the running Proxmox node and tailnet. Appetite: two evenings.

## Problem
Rue can reach the homelab services (Life-Manager, Rue's Arcade, Pi-hole UI, Proxmox UI) only from the home LAN. From the GrapheneOS phone, the E-Ink tablet or the Arch laptop on the road there is no way in.

## Flows
- First rollout: Rue edits the tailnet policy once (tag + autoApprover, snippet from the docs) → merges the PR → CD plans, Rue approves the `infrastructure` apply → empty LXC `tailscale01` exists → Rue creates a tagged pre-auth key → runs `ansible-playbook ansible/playbooks/01_BASE_CONFIGURATION/tailscale.yml` from the laptop, pastes the key at the prompt → TUN passthrough + reboot, Tailscale installed and joined, route auto-approved → Rue configures the clients per checklist.
- Use on the road: phone/tablet (Tailscale app, subnets on) or laptop (`tailscale set --accept-routes=true`) → open `http://192.168.0.223` etc. → traffic goes tailnet → tailscale01 → LAN (SNAT).
- Back home: laptop `tailscale set --accept-routes=false`; phone/tablet keep working through the tunnel while tailscale01 is up.
- Rerun / role change: Rue reruns the operator playbook, key prompt left empty → no changes on a converged host.
- Rebuild of tailscale01 (new CTID, new node identity): runner applies → Rue removes the stale node in the admin console → reruns the operator playbook with a fresh key → route auto-approved again.

## In scope
- **S1** `tailscale01` is declared in `terraform/environments/homelab/hosts.auto.tfvars`: unprivileged LXC, `192.168.0.230/24`, group `tailscale`, tags incl. `terraform`, nesting on, small sizing; `terraform validate`/plan shows exactly one new container and no change to existing guests.
  - edges: IP or hostname collision → existing unique-hosts sensor fails; CD `deploy-targets.sh` prints "tailscale01 has no 02_SERVICES playbook" for the created guest → expected warning (same as the runners), not a failure, and documented; vmid not pinned (Proxmox assigns).
- **S2** The operator playbook `ansible/playbooks/01_BASE_CONFIGURATION/tailscale.yml` first runs `proxmox_lxc_tun` for `tailscale01` (enabled via `host_vars/tailscale01/vars.yml`), so after the play `/dev/net/tun` exists in the container.
  - edges: rerun on a host that already has TUN → no config change, no reboot; container recreated (new CTID) → rerun adds the lines to the new `<ctid>.conf`; run from runner01 is not supported (runner key has no node access by design) → documented as workstation-only.
- **S3** The `tailscale` role (restored from `efa9f49^`, adapted) installs Tailscale from the official APT repo for the guest's Debian release (trixie), enables `tailscaled`, and sets IPv4 + IPv6 forwarding persistently.
  - edges: rerun → `changed=0`; release hardcoded to bookworm in the old role → derived from facts or defaulted to trixie; forwarding sysctl not writable in the unprivileged container → task fails loudly (see R1), never silently skipped.
- **S4** On a host that is not logged in, the role joins with `--auth-key <prompted key> --advertise-routes=192.168.0.0/24 --advertise-tags=tag:subnet-router --accept-dns=false`, key never logged (`no_log`). The key comes from a hidden `vars_prompt` (override with `-e`), not from git.
  - edges: already logged in → no re-auth, empty prompt accepted, no key needed; not logged in and empty key → fails before `tailscale up` with a message saying how to create a tagged key; invalid/expired key → `tailscale up` error surfaces, no partial state claimed as success; advertise settings changed in vars on a running node → converged via `tailscale set` without re-auth.
- **S5** The docs contain the one-time tailnet policy snippet (`tagOwners` for `tag:subnet-router`, `autoApprovers.routes` `192.168.0.0/24` → `tag:subnet-router`); with it applied, the router's route is approved without a click and the tagged node has no key expiry.
  - edges: policy not applied → route shows "awaiting approval"; documented as the first troubleshooting line. Applying the policy is manual (admin console), not code.
- **S6** From a tailnet client outside the home network, `http://192.168.0.223`, `http://192.168.0.227`, `http://192.168.0.225/admin` and `https://192.168.0.22:8006` answer, with no static route on the home router (Tailscale SNAT default).
  - edges: tailscale01 down → off-LAN clients lose access, nothing else breaks; Pi-hole sees queries from 192.168.0.230 (SNAT) → answered (DNS over the tunnel is not the use case here, IP-only).
- **S7** A client checklist in the docs covers the GrapheneOS phone and E-Ink tablet (log in, "use Tailscale subnets" on) and the Arch laptop (default `--accept-routes=false`; on the road `tailscale set --accept-routes=true`, back home `=false`), and states why: a LAN host that accepts the /24 route loses its LAN path when tailscale01 stops (previous incident).
  - edges: phone/tablet at home with Tailscale on → LAN traffic hairpins via tailscale01, works while it is up; if it is down → switch the app off (documented).
- **S8** `docs/tailscale-subnet-router.md` matches the tree: no CT 230 / `partygames01` / `03_SERVICES` / manual bootstrap step / local `terraform apply`; describes the rollout and rebuild flows above. Stale Tailscale references in `README.md`, `terraform/README.md`, `docs/terraform-ansible-split.md` and the `proxmox_lxc_tun` comments point to the new playbook.
  - edges: none (docs only).

## Non-goals
- Service names / DNS (`*.home.arpa`, Pi-hole local records, Split DNS) — Rue chose IP-only for now; split off below.
- Exit node — Rue declined.
- Headscale / self-hosted control server — Rue chose Tailscale SaaS.
- Tailnet policy, keys or approvals as code (Tailscale Terraform provider) — manual console step, already a roadmap item.
- Other people in the tailnet, per-device ACLs — only Rue's three devices; default allow-all policy plus the tag.
- Automatic accept-routes toggling on the laptop (NetworkManager dispatcher) — belongs in dotfiles.
- CD deploying the tailscale role on merge — runner cannot reach the node; operator playbook like the runners.
- IPv6 subnet routes, TLS/HTTPS for the services, Tailscale on other guests or the node.
- Fixing `deploy.yml`'s `workflow_dispatch` list (pihole missing) — unrelated finding.

## Codebase touchpoints
- `terraform/environments/homelab/hosts.auto.tfvars` — new `tailscale01` entry (explorer: network/guests)
- `ansible/playbooks/01_BASE_CONFIGURATION/tailscale.yml` — new operator playbook: play 1 `proxmox_lxc_tun` (gather_facts false), play 2 `common` + `tailscale`, mirrors `efa9f49^:ansible/playbooks/03_SERVICES/tailscale.yml` (explorer: deploy path)
- `ansible/roles/tailscale/` — restored from `efa9f49^:ansible/roles/tailscale/*`, trixie repo URLs verified at pkgs.tailscale.com (explorer: deploy path, existing plan)
- `ansible/inventory/host_vars/tailscale01/vars.yml` — `proxmox_lxc_tun_enabled: true`; no vault file (explorer: existing plan, secrets)
- `ansible/inventory/group_vars/` — `tailscale` group chains to `lxc_container_proxmox` → `proxmox_guest` (explorer: network/guests)
- `ansible/roles/proxmox_lxc_tun/` — reused unchanged except comments; delegates to `proxmox_node_ip` with the workstation's node key (explorer: existing plan, deploy path)
- `scripts/proof.sh` — ansible-lint + syntax-check cover the new role/playbook automatically; `git add` before `--all` (explorer: secrets/CI)
- `docs/tailscale-subnet-router.md`, `README.md`, `terraform/README.md`, `docs/terraform-ansible-split.md` — docs (explorer: existing plan)

## Risks
- R1 IPv4/IPv6 forwarding sysctls in an unprivileged LXC → accepted: they are network-namespace scoped and normally writable inside the CT; the role sets and verifies them and fails loudly otherwise. Proven at the first live run.
- R2 Live behaviour (S2, S4–S6) can only be proven after merge, because only the runner applies Terraform and the host doesn't exist before → accepted: Gate 2 evidence is lint/syntax-check/offline checks plus a post-merge manual checklist; the ⚠ steps run on Rue's go.
- R3 LAN host accepting the /24 route loses its LAN path (previous incident) → resolved: S7 laptop default off, documented.
- R4 Pre-auth key expires or is single-use → resolved: prompted at run time, only needed for a join.
- R5 Phone/tablet at home lose LAN access while tailscale01 is down and the app is on → accepted, documented in S7.
- R6 `deploy-targets.sh` warns about a created guest without a 02_SERVICES playbook → accepted: warning only, documented in S1.

## Decisions
- Tailscale SaaS — Rue asked for Tailscale; free tier is enough.
- IP-only, `--accept-dns=false` — smallest useful step; names later.
- Subnet router only, advertises the whole `192.168.0.0/24` — single flat LAN, single user.
- Operator playbook in `01_BASE_CONFIGURATION/`, never run by CD — the runner has no node access by design; a merge must never restart the VPN.
- `tag:subnet-router` + `autoApprovers` — rebuilds need no clicks, tagged nodes don't expire.
- Pre-auth key via hidden prompt, not ansible-vault — the key is only needed once, then dead; no secret commit per rebuild. Deliberate deviation from the vault convention.
- IP `192.168.0.230` — the documented address, free.
- Clients are configured by hand from a checklist — apps already installed, not Ansible-managed.

## Done when
- With Wi-Fi off on the GrapheneOS phone, Life-Manager (`.223`), Rue's Arcade (`.227`), the Pi-hole admin (`.225/admin`) and the Proxmox UI (`.22:8006`) open; same from the E-Ink tablet.
- From the Arch laptop on a foreign network with `--accept-routes=true`, `ssh` to a guest works; at home with `--accept-routes=false` and tailscale01 stopped, the laptop still reaches the node.
- The admin console shows `tailscale01` tagged `tag:subnet-router`, route approved without a click, key expiry disabled.
- A second run of the operator playbook (empty key prompt) reports `changed=0`.
- `scripts/proof.sh --all` is green and the PR's CI is green.

## Split off
- Local service names: `home.arpa` records in Pi-hole + Tailscale Split DNS, `--accept-dns` on clients.
