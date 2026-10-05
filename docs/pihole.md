# Pi-hole

Pi-hole v6 on `pihole01` (LXC 225, `192.168.0.225`), the LAN's DNS sinkhole.
It runs natively, not in a container: Terraform creates the guest, the `pihole`
role installs and configures it, and FTL serves both DNS (port 53 on `eth0`)
and the admin UI (`http://192.168.0.225/admin`). There is no nginx in front of
it. Upstreams are `8.8.8.8` and `1.1.1.1`; everything else is Pi-hole's default.

| Piece | Where |
|---|---|
| Guest | `pihole01` in `terraform/environments/homelab/hosts.auto.tfvars`, group `pihole` |
| Playbook | `ansible/playbooks/03_SERVICES/pihole.yml` (`common`, then `pihole`) |
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

## First-time apply

Everything here is run by hand from the repo root. Order matters.

1. **Router fallback.** In the router, make sure a second resolver is
   configured and the router does not yet depend on `.225` alone. Manual.
2. **Vault file.** Create `ansible/inventory/host_vars/pihole01/vault.yml`
   with `pihole_password` as an inline vaulted string, encrypted with the
   password in `~/.config/homelab/vault_pass`:

       ansible-vault encrypt_string --stdin-name pihole_password

   Type the value, end with Ctrl-D, paste the `pihole_password: !vault |`
   block into the file. The password is also what you log in with later.
3. **Terraform.** The plan must show exactly one new LXC, `pihole01`, and no
   change to any other host:

       terraform -chdir=terraform/environments/homelab plan
       terraform -chdir=terraform/environments/homelab apply

4. **Refresh the inventory** with `scripts/fetch-inventory.sh` (the file is
   gitignored and rendered on the runner). `pihole01` appears in group
   `pihole`. Until then `hosts: pihole` matches nothing.
5. **Bootstrap** the new guest:

       ansible-playbook ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml -l pihole01

6. **Dry run:**

       ansible-playbook ansible/playbooks/03_SERVICES/pihole.yml --check

7. **Real run:**

       ansible-playbook ansible/playbooks/03_SERVICES/pihole.yml

   It ends with the smoke check: `dig @127.0.0.1 example.org` answers on the
   guest and `http://127.0.0.1/admin/` returns 200 or the login redirect. A
   failed check fails the play.
8. **Run it a second time.** The recap must show `changed=0`, and
   `pihole-FTL` must not have restarted (`systemctl status pihole-FTL` on the
   guest, uptime unchanged).
9. **Check from the LAN:**

       dig @192.168.0.225 example.org

   then open `http://192.168.0.225/admin` and log in with the vault password.
10. **Optional:** point the router's DHCP resolver at `.225`, keeping the
    fallback from step 1.

**A merge before the apply is a no-op.** `deploy.yml` maps the diff to
`pihole.yml`, but with no `pihole01` in the committed inventory the play is
skipped, not failed. Apply first, then merge.

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

Before merging, `ansible-playbook ansible/playbooks/03_SERVICES/pihole.yml --check`
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
- **Rebuild from scratch.** Terraform owns the guest, so recreate it
  (`terraform destroy -target` for that one guest, then steps 3 to 9 above).
  The router fallback keeps the LAN resolving meanwhile. Pi-hole's config and
  gravity database are not backed up; a rebuild starts from the defaults the
  role sets.
