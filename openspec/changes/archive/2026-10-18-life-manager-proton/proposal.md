## Why

Life-Manager v0.6.0 on life-manager01 can sync to Proton Calendar, but only if the `proton` binary, its env vars and a logged-in session exist on the host. Hand-edits there are overwritten by the next Ansible deploy, because `env.j2` does not know the vars. The `life_manager` role has to own all three, behind a flag.

## What Changes

- `life_manager` role, new `tasks/proton.yml` (imported from `main.yml`, gated on `life_manager_proton_enabled`): installs proton-cli v5.1.0 to `/usr/local/bin/proton` (pinned URL + sha256 as role defaults), creates `<data_dir>/.config/proton-cli` (0700, `life-manager`), and reports a missing login session with the exact login command. It never logs in.
- `templates/env.j2` gains `PROTON_CLI`, `PROTON_PROFILE`, `XDG_CONFIG_HOME` only when the flag is on.
- `host_vars/life-manager01/vars.yml` sets the flag to `true`; the role README gets the vars and a login/re-login runbook.
- New offline fixture test `scripts/tests/life-manager-proton.sh`, wired into `scripts/proof.sh` for `ansible/roles/life_manager/*`, `host_vars/life-manager01/*` and the test itself.
- Merging deploys it (CD runs `02_SERVICES/life-manager.yml` on runner01). That merge is the live step; it is not a task.

## Capabilities

### New Capabilities
- `life-manager-proton`: what the `life_manager` role installs, renders and reports for Proton Calendar sync. A new capability rather than a delta because no existing spec owns the role's runtime configuration: `continuous-deployment` covers the pipeline, `sqlite-backups` the backup registry, `release-bump` the version PRs. Extending one of those would misfile the requirements.

### Modified Capabilities
- none

## Impact

- Files: `ansible/roles/life_manager/{defaults/main.yml,tasks/main.yml,tasks/proton.yml,templates/env.j2,README.md}`, `ansible/inventory/host_vars/life-manager01/vars.yml`, `scripts/proof.sh`, `scripts/tests/life-manager-proton.sh`.
- `scripts/deploy-targets.sh` already maps these paths to `life-manager.yml`; no change.
- Merge restarts life-manager once (env change) and runs the smoke check as usual. The new restart is covered by the existing rollback only for release swaps; the env change itself has no rollback (R3: a failed download stops the play before env changes).

## Non-Goals

- Automated login (password/TOTP in vault): CAPTCHA cannot be automated and it puts the account password on runner01's path.
- Backing up the Proton session: re-login after a rebuild is cheap.
- Egress firewall changes: life-manager01 has no egress filtering.
- A separate `proton_cli` role: single consumer; `check_runner` precedent.
- arm64 or other arches.
- Removing the binary when the flag is turned off.

## Done criteria

- [ ] `scripts/proof.sh --all` is green, including the `life-manager-proton fixtures` sensor, `ansible-lint` and the syntax check of `life-manager.yml`.
- [ ] Rendering `env.j2` with the flag off is byte-identical to today's file; with it on, it has exactly the three extra lines.
- [ ] Defaults hold version v5.1.0, the release URL and sha256 `51ac1dbb…34d7`.
- [ ] Post-merge, by hand (checklist below): deploy green, warning shown, login, no warning, `/sync` works.

## Appetite

One evening. Exceeding it means renegotiating scope.

## Post-merge checklist (manual, Rue; not tasks)

1. Merge on Rue's go after CI green; watch the `deploy` run for `life-manager.yml` on runner01: green.
2. Deploy log shows `Proton login needed` with the full command; `/usr/local/bin/proton --version` on life-manager01 answers v5.1.0.
3. Run the reported command on life-manager01 (`sudo -u life-manager env XDG_CONFIG_HOME=/var/lib/life-manager/.config /usr/local/bin/proton account login --profile default`).
4. Re-run the deploy (Actions, run workflow): no login warning.
5. In the app: `/sync` then "Sync now"; events appear in Proton Calendar.

## Additions beyond scope.md

- none
