## 1. Prerequisites (out-of-band, Tailscale admin console)

- [ ] 1.1 Create/confirm a Tailscale account and tailnet
- [ ] 1.2 Generate a pre-auth key (reusable or ephemeral as preferred) for `tailscale01`

## 2. Inventory wiring

- [x] 2.1 Add a `[tailscale]` group to `inventory/hosts` with `tailscale01 ansible_host=192.168.0.<x> ansible_user=ansible`
- [x] 2.2 Nest `tailscale` under `[lxc_container_proxmox:children]`
- [x] 2.3 Create `inventory/host_vars/tailscale01/vars.yml` with LXC sizing (`lxc_cores: 1`, `lxc_memory: 512`, `lxc_swap: 512`, `lxc_disk_gb: 4`), `id` (CTID), and `tailscale_advertise_routes: 192.168.0.0/24`
- [x] 2.4 Create `inventory/host_vars/tailscale01/vault.yml` with the pre-auth key appended as the **last** entry; encrypt with ansible-vault
  - Created with an inline `!vault`-encrypted **placeholder**; operator replaces it via task 1.2 (`ansible-vault edit`).

## 3. Provisioning: TUN passthrough (host-level)

- [x] 3.1 Add a provisioning task that edits `/etc/pve/lxc/<ctid>.conf` on `proxmox1` to add `lxc.cgroup2.devices.allow: c 10:200 rwm` and `lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file` (delegated to the host; idempotent; not in the app role)
  - Implemented as `roles/proxmox_lxc_tun` (blockinfile, gated by `proxmox_lxc_tun_enabled`), wired into `01_PROVISIONING/lxc_proxmox.yml`.
- [x] 3.2 Ensure the task restarts/recreates the container so the device mount takes effect before service bring-up
  - Reboot + SSH-wait implemented as handlers (flush at end of the provisioning play, before the `common` pass).
- [ ] 3.3 Provision the container by running `playbooks/01_PROVISIONING/lxc_proxmox.yml` limited to `tailscale01` *(operator run — needs live Proxmox)*
- [ ] 3.4 Base-configure the host (`playbooks/02_BASE_CONFIGURATION/*`) so `ansible` user + SSH are set up *(operator run — needs live host)*

## 4. `roles/tailscale` role

- [x] 4.1 Scaffold the role (`defaults/`, `handlers/`, `meta/`, `tasks/`) with `tasks/main.yml` as an import-only hub
- [x] 4.2 `defaults/main.yml`: `tailscale_advertise_routes`, `tailscale_accept_dns: false`, `tailscale_up_extra_args: ""`, package name
- [x] 4.3 `tasks/install.yml`: add the official Tailscale APT repo/key and install the `tailscale` package via `ansible.builtin.apt` (single list)
- [x] 4.4 `tasks/configure.yml`: set persistent `net.ipv4.ip_forward=1` and `net.ipv6.conf.all.forwarding=1` via `ansible.posix.sysctl`
- [x] 4.5 `tasks/service.yml`: ensure `tailscaled` enabled+running (handler); run `tailscale up --authkey=<vault> --advertise-routes={{ tailscale_advertise_routes }} --accept-dns=false`, guarded so re-runs are idempotent (check `tailscale status` first)
- [x] 4.6 `handlers/main.yml`: restart `tailscaled`

## 5. Service playbook

- [x] 5.1 Create `playbooks/03_SERVICES/tailscale.yml` targeting the `tailscale` group and applying `roles/tailscale`

## 6. Manual completion (admin console)

- [ ] 6.1 Approve the advertised `192.168.0.0/24` route for `tailscale01`
- [ ] 6.2 Disable key expiry on the `tailscale01` node so the tunnel does not lapse

## 7. Verification

- [x] 7.1 `ansible-playbook --syntax-check` on the new/changed playbooks; run `ansible-lint` and clear warnings
  - Both playbooks pass `--syntax-check`; `ansible-lint` clean apart from the pre-existing repo-wide SPDX `yaml[comments]` pattern.
- [ ] 7.2 On `tailscale01`, confirm `tailscale status` shows connected and advertising the route, and `/dev/net/tun` is present *(operator — needs live host)*
- [ ] 7.3 From a remote Tailscale device with subnet routes enabled, reach `192.168.0.224` (partygames) and the Proxmox UI at `192.168.0.22:8006` *(operator — needs live tunnel)*
- [ ] 7.4 Confirm no inbound ports are forwarded on the home router *(operator)*

## 8. Documentation

- [x] 8.1 Add a short runbook (e.g. `docs/tailscale-subnet-router.md`) covering the manual console steps, re-auth/key rotation, and rollback
