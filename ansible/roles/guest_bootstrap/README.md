# guest_bootstrap

Converges the SSH keys authorised for the `ansible` account on a guest.

The `ansible` user, its sudo rule and python3 come from the homelab LXC
template (`scripts/build-lxc-template.sh`), which also bakes in the guest and
deploy public keys so a new guest is reachable the moment it boots. The template
is only a first-contact seed; this role is the source of truth. It sets
`ansible`'s `authorized_keys` to exactly the keys in `ansible/keys/`
(`exclusive`), so it is how:

- a rotated key reaches guests created from an older template, and
- the deploy key leaves `runner01`, which the template put it on
  (`guest_bootstrap_authorize_deploy_key: false` in `group_vars/github_runner`).

`proxmox_node` hosts never run this role.

**No passwords anywhere.** Terraform sets no root password, the template sets
none either; `pct enter <ctid>` from the node is the console fallback. See
`docs/terraform-ansible-split.md`.

## Usage

Via `playbooks/02_BASE_CONFIGURATION/bootstrap.yml`, which runs this role and
then `common` as `ansible`. Safe to re-run.

To re-key without locking yourself out, authorise the old key for one run and
connect with it, then switch `ansible.cfg` to the new key and run again:

    ansible-playbook playbooks/02_BASE_CONFIGURATION/bootstrap.yml \
      -e '{"guest_bootstrap_extra_public_keys": ["<old public key>"]}' \
      --private-key ~/.ssh/<old key>

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `guest_bootstrap_user` | `ansible` | Account whose keys are managed |
| `guest_bootstrap_ssh_public_key` | `ansible/keys/guest_ed25519.pub` | Workstation guest key |
| `guest_bootstrap_deploy_public_key_path` | `ansible/keys/deploy_ed25519.pub` | Deploy runner's key |
| `guest_bootstrap_authorize_deploy_key` | `true` | `false` on the runner itself (`group_vars/github_runner`) |
| `guest_bootstrap_extra_public_keys` | `[]` | Extra keys for one re-keying run |
