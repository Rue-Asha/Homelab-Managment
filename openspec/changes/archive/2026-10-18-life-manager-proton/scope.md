# Scope: life-manager-proton

Triage: tweak · live — the `life_manager` role installs proton-cli (pinned + checksum), adds the Proton env vars behind a flag, prepares the session dir and reports a missing login; merging deploys to life-manager01. Appetite: one evening.

## Problem
Life-Manager v0.6.0 (deployed on life-manager01) can sync to Proton Calendar, but only if the `proton` binary, its env vars and a logged-in session exist on the host. Today that would be hand-edits that the next Ansible deploy overwrites (`env.j2` doesn't know the vars).

## Flows
- Deploy: merge to `main` → runner01 runs `02_SERVICES/life-manager.yml` → proton-cli installed, env rendered, service restarted → play reports "Proton login needed" with the exact command while no session exists.
- First login (manual, once, post-merge): Rue runs the reported command on life-manager01 → next deploy reports no warning; in the app `/sync` → "Sync now" → events in Proton.
- Re-login (CAPTCHA/expired session, shown on `/sync`): same command; no Ansible run needed.

## In scope
- **S1** With `life_manager_proton_enabled: true` the role downloads `proton-cli_linux_amd64` v5.1.0 from `https://github.com/roman-16/proton-cli/releases/download/v5.1.0/proton-cli_linux_amd64` to `/usr/local/bin/proton` (root:root, 0755), verified against the pinned sha256 `51ac1dbb4041a6c5607a0853a7ef405737f497bd207d65e0957b9d4b0c0934d7` (from the release's `checksums.txt`, fetched 2026-10-18). Version, URL, sha256 and bin path are role defaults (`life_manager_proton_version`, `_url`, `_sha256`, `_bin`), pinned like `check_runner`'s tools.
  - edges: re-run with the binary in place → no change (get_url checksum idempotence); checksum mismatch → the play fails before the env is touched; flag false → nothing downloaded, nothing removed; host arch not x86_64 → assert fails with a message naming the arch.
- **S2** With the flag on, `templates/env.j2` adds `PROTON_CLI={{ life_manager_proton_bin }}`, `PROTON_PROFILE={{ life_manager_proton_profile }}` (default `default`) and `XDG_CONFIG_HOME={{ life_manager_data_dir }}/.config`; with the flag off the rendered env file is byte-identical to today's (no restart).
  - edges: env change → existing `Restart life-manager` handler fires once.
- **S3** With the flag on, `{{ life_manager_data_dir }}/.config` and `.config/proton-cli` exist, owned `life-manager:life-manager`, mode 0700 (inside the unit's only `ReadWritePaths`).
  - edges: dirs already present with a session → contents untouched.
- **S4** With the flag on, the role checks (`ansible.builtin.stat`, no CLI call, no network) for `{{ life_manager_data_dir }}/.config/proton-cli/sessions/{{ life_manager_proton_profile }}.json`; if missing it prints a warning naming the exact command `sudo -u life-manager env XDG_CONFIG_HOME=/var/lib/life-manager/.config /usr/local/bin/proton account login --profile default`. It never fails the play and runs outside the smoke-check/rollback path.
  - edges: session present → no warning; check mode → the stat still runs and reports.
- **S5** `life_manager_proton_enabled: true` in `host_vars/life-manager01/vars.yml`; the role README documents the vars, the one-time login, re-login, and that the session is not covered by `sqlite_backups` (re-login after a rebuild).
  - edges: none (docs + one var).

## Non-goals
- Automated login (password/TOTP in vault) — CAPTCHA can't be automated and it would put the account password on runner01's path; Rue logs in once by hand (decided 2026-10-18).
- Backing up the Proton session — re-login after a rebuild is cheap.
- Egress firewall changes — explorer found no egress filtering on life-manager01 (only runner roles use `egress_firewall`); HTTPS to `*.proton.me` is open.
- A separate `proton_cli` role — single consumer; precedent `check_runner` installs its own tools.
- arm64 / other arches.
- Removing the binary when the flag is turned off.

## Codebase touchpoints
- `ansible/roles/life_manager/tasks/proton.yml` (new), imported from `tasks/main.yml` — install, dirs, session check (explorer).
- `ansible/roles/life_manager/defaults/main.yml` — flag + pins (explorer).
- `ansible/roles/life_manager/templates/env.j2` — conditional env lines (explorer).
- `ansible/roles/life_manager/README.md` — vars + login runbook (explorer).
- `ansible/inventory/host_vars/life-manager01/vars.yml` — enable flag (explorer).
- `scripts/tests/` + `scripts/proof.sh` — new offline fixture test rendering `env.j2` on/off, path-triggered like `tailscale.sh` (explorer).
- `scripts/deploy-targets.sh` — already maps `roles/life_manager` and `host_vars/life-manager01` changes to `life-manager.yml` (explorer; no change).

## Risks
- R1 Merge = deploy to life-manager01 (runner01) → accepted as the ⚠ live step: PR only, merge on Rue's go after CI; evidence includes `ansible-playbook --check --diff` against life-manager01 if reachable from the workstation, else stated as not run.
- R2 `--check` skips command/shell tasks and proves little (repo learning) → resolved: offline fixture test is the main proof; live behaviour is proven only after merge (post-merge checklist).
- R3 GitHub download fails during deploy → accepted: play fails before the env changes; current release keeps running.

## Decisions
- proton-cli lives in the `life_manager` role, new `tasks/proton.yml` — single consumer, `check_runner` precedent.
- Pinned literal sha256 in defaults, not fetched `checksums.txt` — repo practice.
- Session check by file stat, not a `proton` call — no network, no ToS-relevant API traffic.
- Login stays manual; the play only reports it — Rue's choice.

## Done when
- `scripts/proof.sh --all` green, incl. the new fixture test (env on/off, defaults pinned).
- Post-merge (manual, Rue): deploy run green; play shows the login warning; after the login command a re-run shows none; `/sync` → "Sync now" → events appear in Proton.

## Split off
- none
