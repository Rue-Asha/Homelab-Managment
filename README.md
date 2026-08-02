# Homelab-Managment

Ansible repository that configures every machine in my Proxmox homelab. Nothing
is set up by hand: each service gets its own lightweight LXC, and a playbook is
the only way in.

> **Docs:** project write-up on the blog —
> [rue-asha.github.io/projects/homelab](https://rue-asha.github.io/projects/homelab/).
> This README only covers running the automation itself.

## What's here

| Service / role | Purpose |
|---|---|
| `pihole` | Network-wide DNS filtering |
| `tailscale` | Subnet router, remote access into the LAN |
| `nginx` | Host-level reverse proxy in front of each web service |
| `nodejs` | Runtime for the SvelteKit services below |
| `life-dashboard` | Deploys [Life-Managment-Dashboard](https://github.com/Rue-Asha/Life-Managment-Dashboard) |
| `partygames` | Deploys [Party-Games](https://github.com/Rue-Asha/Party-Games) |
| `retropie` | Retro-games box |
| `common` | Base host hardening shared by every guest |
| `proxmox_lxc*`, `proxmox_vm*` | Provisioning: create LXCs/VMs from template or ISO |

Application services follow an **app-per-LXC, two-repo model**: this repo
configures the host and installs the runtime; the application code lives in
its own repo and is checked out + built on the host at a pinned git tag (no
Docker, no CI required — `systemd` supervises the process). See
`docs/party-games-webservice-architecture.md` for a worked example.

## Repo layout

```
playbooks/
  00_OPERATIONAL/         # ad-hoc / day-2 ops: backups, snapshots, maintenance
  01_PROVISIONING/        # create infrastructure: LXCs, VMs from ISO/template
  02_BASE_CONFIGURATION/  # post-provision host setup: users, SSH, hardening
  03_SERVICES/            # application install & config
inventory/                # hosts + group_vars/host_vars (no vars in `hosts` itself)
roles/                    # standard Galaxy role structure
docs/                     # architecture notes and implementation plans
openspec/                 # OpenSpec change proposals for larger pieces of work
```

The `NN_` prefix on playbook categories encodes the order a fresh host moves
through them (00 → 03).
