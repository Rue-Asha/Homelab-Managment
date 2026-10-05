# pihole

Installs Pi-hole v6 natively on a Debian 13 guest (app-per-LXC, no Docker) and
converges its settings and admin password. FTL serves the web UI itself on :80;
there is no nginx and no lighttpd. Deployed by `ansible/playbooks/03_SERVICES/pihole.yml`.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `pihole_version` | none | `pi-hole/pi-hole` core tag including the `v` (e.g. `v6.4.3`). Set in `host_vars/pihole01/vars.yml`. |
| `pihole_password` | none | Admin password, inline `!vault \|` in `host_vars/pihole01/vault.yml`. |
| `pihole_interface` | `eth0` | Listening interface. |
| `pihole_upstream_dns` | `8.8.8.8`, `1.1.1.1` | Upstream resolvers. |
| `pihole_smoke_domain`, `pihole_smoke_url`, `pihole_smoke_retries`, `pihole_smoke_delay` | `example.org`, `http://127.0.0.1/admin/`, `10`, `3` | Smoke check. |

The play fails in `prepare.yml`, before anything on the host changes, when
`pihole_version` or `pihole_password` is missing or the tag does not exist upstream.

## How the pin works

The upstream installer has no version argument. The role clones core at
`pihole_version` into `/etc/.pihole` on a local branch with itself as upstream,
seeds a minimal `/etc/pihole/pihole.toml` (needed for `--unattended`), and runs
`basic-install.sh` from that checkout. It does this only when Pi-hole is absent
or the core version in `/etc/pihole/versions` differs from `pihole_version`.
Only core is pinned: web and FTL follow latest at install time. Afterwards
settings are converged with `pihole-FTL --config` (compared with `-q`), and the
password is checked by `POST /api/auth` and set with `pihole setpassword` only on
a 401. `pihole-FTL` restarts only through the `pihole_restart_ftl` handler.
`verify.yml` asserts the installed core equals the pin and smoke-checks DNS and
the admin URL; a failure fails the play and changes nothing.

## Unverified (no host has run this)

- FTL accepts the partial `pihole.toml` seed and fills the defaults; fallback is a `setupVars.conf` seed.
- `/etc/pihole/versions` has `CORE_VERSION=` lines (with or without `v`; both are handled).
- `pihole-FTL --config -q` output for the upstream array after stripping brackets, quotes and spaces is `8.8.8.8,1.1.1.1`; if not, the setting is rewritten (and FTL restarted) on every run.
- `webserver.api.pwhash` is the key holding the password hash; `/api/auth` answers 401 on a wrong password.
- `pihole setpassword <password>` takes the password as an argument (visible in the process list for that moment).
- FTL starts in the unprivileged LXC (`CAP_SYS_TIME` may be dropped); remedy is a systemd drop-in clearing it from `AmbientCapabilities`.
- Debian 13 is not in upstream's CI images; the installer has no OS gate in v6.4.3.
- `/etc/pihole` ownership after the installer lets FTL (user `pihole`) rewrite the seeded `pihole.toml`.
