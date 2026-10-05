# Pi-hole

Pi-hole v6 on `pihole01` (LXC 225, `192.168.0.225`), the LAN's DNS sinkhole.
It runs natively, not in a container: Terraform creates the guest, the `pihole`
role installs and configures it, and FTL serves both DNS (port 53 on `eth0`)
and the admin UI (`http://192.168.0.225/admin`). There is no nginx in front of
it. Upstreams are `8.8.8.8` and `1.1.1.1`; everything else is Pi-hole's default.

**Status:** `pihole01` is declared in Terraform again, rebuilt from the golden
template. Merging its declaration creates the guest and configures Pi-hole in
one workflow run; see *Create or rebuild*.

| Piece | Where |
|---|---|
| Guest | `pihole01` in `terraform/environments/homelab/hosts.auto.tfvars`, group `pihole` |
| Playbook | `ansible/playbooks/02_SERVICES/pihole.yml` (`common`, then `pihole`) |
| Role | `ansible/roles/pihole` (`prepare`, `packages`, `install`, `configure`, `service`, `verify`) |
| Pinned version | `pihole_version` in `ansible/inventory/host_vars/pihole01/vars.yml` |
| Admin password | `pihole_password` in `ansible/inventory/host_vars/pihole01/vault.yml` (ansible-vault, created by hand) |

## The DNS-outage risk

If the router hands out `192.168.0.225` as the LAN's resolver and `pihole01`
is down or broken, **every client on the LAN loses DNS**. Nothing in this
repo changes the router: pointing it at Pi-hole, and keeping a second resolver
configured on it, is a **manual** step in the router's UI. It is not automated
and no playbook checks it.

Until you have run the checks below, leave the router pointing at its current
resolver. Pointing it at `.225` is the last, optional step, and only with a
fallback resolver (for example `1.1.1.1`) set at the same time. Terraform's
`network_nameservers` deliberately does not use Pi-hole, so `runner01` and the
other guests keep resolving when it is down.

## Create or rebuild

Creation runs on `runner01` from `deploy.yml`, not from the workstation:
merge → `plan` → `infrastructure` approval → `apply` → `deploy`. The `apply`
job pins the new guest's SSH host key into the runner's `known_hosts`, and the
`deploy` job of the same run passes the created guests to `deploy-targets.sh`,
so `02_SERVICES/pihole.yml` runs and ends with its smoke check.

1. **Router fallback.** In the router, make sure a second resolver is
   configured and the router does not yet depend on `.225` alone. Manual.
2. **Vault file.** `ansible/inventory/host_vars/pihole01/vault.yml` holds
   `pihole_password` as an inline vaulted string, encrypted with the vault
   password the runner holds (`~/.config/homelab/vault_pass` on the
   workstation). To create or replace it:

       ansible-vault encrypt_string --stdin-name pihole_password

   Type the value, end with Ctrl-D, paste the `pihole_password: !vault |`
   block into the file. The password is also what you log in with later.
3. **Pre-merge `known_hosts` check.** The `apply` job never overwrites an
   existing key, so a stale entry for the address fails the deploy with "host
   key changed". On runner01, as `github-runner`:

       ssh-keygen -F 192.168.0.225 -f ~/.ssh/known_hosts

   It must find nothing. If it does, remove the entry with `ssh-keygen -R
   192.168.0.225 -f ~/.ssh/known_hosts` before merging.
4. **Merge.** The plan must show exactly one new LXC, `pihole01`, and no
   change to any other host. Approve `infrastructure`. The run ends with the
   `pihole.yml` smoke check: `dig @127.0.0.1 example.org` answers on the guest
   and `http://127.0.0.1/admin/` returns 200 or the login redirect. A failed
   check fails the run.
5. **Run it a second time** (re-run the workflow, or `ansible-playbook
   ansible/playbooks/02_SERVICES/pihole.yml` from the workstation). The recap
   must show `changed=0`, and `pihole-FTL` must not have restarted
   (`systemctl status pihole-FTL` on the guest, uptime unchanged).
6. **Check from the LAN:**

       dig @192.168.0.225 example.org

   then open `http://192.168.0.225/admin` and log in with the vault password.
7. **Optional:** point the router's DHCP resolver at `.225`, keeping the
   fallback from step 1.

If the deploy fails after a successful `apply`, the guest exists: fix the
cause and re-run `pihole.yml`; do not destroy and recreate unless the guest
itself is wrong.

## What the pin covers

`pihole_version` pins the `pi-hole/pi-hole` **core** tag (including the `v`,
currently `v6.4.3`). The upstream installer has no version argument, so the
role checks that tag out and runs the installer from it. The web UI and FTL are
versioned independently and the installer takes their **latest** release at
install time. The installer only runs when Pi-hole is absent or its core
version differs from `pihole_version`; a plain converge run never touches it,
and nothing updates Pi-hole on its own unless someone runs `pihole -up` on the
guest. `verify.yml` asserts the core version and prints the web and FTL
versions, so a drift shows in the play output.

## Watch on the first run

Not verified before the first real run; each has a known fallback.

- **Partial `pihole.toml`.** The role seeds a minimal file (upstreams and
  interface) and expects FTL to fill in the defaults. If FTL rejects it, the
  fallback is a `setupVars.conf` seed, which the installer migrates.
- **FTL in the unprivileged LXC.** Binding :53 and :80 should work. If
  `pihole-FTL` fails to start on its capability line (`CAP_SYS_TIME` is
  dropped by LXC defaults), the remedy is a systemd drop-in clearing it from
  `AmbientCapabilities`.
- **Debian 13.** Upstream tests Ubuntu images; v6.4.3 has no OS gate, but
  support is unconfirmed.
- **Password check.** The role compares the password by logging in at
  `/api/auth`; the response shape for a wrong password is unconfirmed. If the
  second run reports the password task as changed, look here.
- **Installed-version read.** How the role reads the installed core version
  (`pihole -v -p` or `/etc/pihole/versions`) and its format are unconfirmed. If
  the second run re-runs the installer, look here.
- **Secrets.** `pihole_password` tasks use `no_log`; check that the first
  run's output contains no password anyway.

## Bump the version

A bump is a PR that changes `pihole_version` in
`ansible/inventory/host_vars/pihole01/vars.yml` to a newer `pi-hole/pi-hole`
tag. Merging it deploys: `deploy.yml` maps the change to `pihole.yml` and runs
it. The installer runs once, then the smoke check. Because web and FTL float,
read the play output for their versions after the run.

Before merging, `ansible-playbook ansible/playbooks/02_SERVICES/pihole.yml --check`
from the workstation is fine. A bump takes DNS down briefly while FTL
restarts; do it when the LAN can live without it, or while the router fallback
is in effect.

## Recovery

- **DNS is down on the LAN.** Restore the router's resolver to the fallback
  first (manual), then debug at leisure. `pct enter 225` on `proxmox1` is the
  console; there is no guest root password.
- **The smoke check failed.** Nothing is rolled back (there is no release
  layout) and nothing is restarted. On the guest: `systemctl status
  pihole-FTL`, `journalctl -u pihole-FTL`, `dig @127.0.0.1 example.org`. Fix
  the cause and re-run `pihole.yml`.
- **A bad bump.** Revert the PR; the merge re-runs the installer from the
  previous core tag. Settings and the gravity database stay in place.
- **Rebuild from scratch.** Terraform owns the guest, so remove `pihole01`
  from `hosts.auto.tfvars` in one PR (the destroy goes through the approved
  `apply`), delete its `known_hosts` line on runner01, then add it back in a
  second PR and follow *Create or rebuild*. The router fallback keeps the LAN
  resolving meanwhile. Pi-hole's config and
  gravity database are not backed up; a rebuild starts from the defaults the
  role sets.
