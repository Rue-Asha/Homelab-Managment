# guest_bootstrap

Prepares a freshly provisioned guest for SSH-based Ansible management.

Terraform seeds the SSH key into the guest's **root** account at creation. This
role connects in as root and establishes the unprivileged `ansible` account that
every later playbook uses:

1. ensure a Python interpreter (`raw` — the one justified use in this repo)
2. install `sudo`
3. create the `ansible` user
4. drop a `visudo`-validated passwordless sudoers file
5. authorise the SSH key for that user

It replaces `proxmox_lxc_bootstrap`, which did the same work through `pct exec`
on the Proxmox node because Ansible was also doing the provisioning. With
Terraform owning guest lifecycle, this is a plain guest-side concern and needs
no access to the node.

**No passwords anywhere.** Terraform sets no root password and this role sets
none either; `pct enter <ctid>` from the node is the console fallback. See
`docs/terraform-ansible-split.md`.

## Usage

Via `playbooks/02_BASE_CONFIGURATION/bootstrap.yml`, which runs this role and
then `common`. One-shot: `common` closes root SSH login at the end, so the play
that connects as root cannot run again — by design.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `guest_bootstrap_user` | `ansible` | Account later playbooks connect as |
| `guest_bootstrap_user_shell` | `/bin/bash` | Login shell |
| `guest_bootstrap_user_home` | `/home/<user>` | Home directory |
| `guest_bootstrap_ssh_public_key` | `~/.ssh/Proxmox.pub` | Key authorised for that account |
| `guest_bootstrap_packages` | `[sudo]` | Packages needed before `common` runs |
| `guest_bootstrap_sudoers_path` | `/etc/sudoers.d/<user>` | Drop-in location |

`guest_bootstrap_connect_user` (playbook-level, default `root`) overrides the
connection user for the first play.
