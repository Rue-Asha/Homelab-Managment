## ADDED Requirements

### Requirement: proton-cli is installed from a pinned, checksummed release

With `life_manager_proton_enabled: true`, the `life_manager` role SHALL download `proton-cli_linux_amd64` v5.1.0 from `https://github.com/roman-16/proton-cli/releases/download/v5.1.0/proton-cli_linux_amd64` to `/usr/local/bin/proton` (owner `root:root`, mode `0755`), verified against sha256 `51ac1dbb4041a6c5607a0853a7ef405737f497bd207d65e0957b9d4b0c0934d7`. Version, URL, sha256 and bin path SHALL be role defaults (`life_manager_proton_version`, `_url`, `_sha256`, `_bin`), not task literals. The flag SHALL default to `false`.

#### Scenario: The pinned binary is installed
- **WHEN** the proton tasks run with the flag on and a local `file://` artifact whose sha256 matches `life_manager_proton_sha256`
- **THEN** the artifact is at `life_manager_proton_bin` with identical content and mode `0755`, and the download task declares owner `root` and group `root`
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: The pinned binary is installed")

#### Scenario: Version, URL, sha256 and bin path are role defaults
- **WHEN** `defaults/main.yml` is rendered without overrides
- **THEN** `life_manager_proton_enabled` is false, `_version` is `v5.1.0`, `_url` equals the release URL above, `_sha256` equals the pinned digest and `_bin` is `/usr/local/bin/proton`
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: Version, URL, sha256 and bin path are role defaults")

#### Scenario: A second run changes nothing
- **WHEN** the proton tasks run twice against the same host with the binary in place
- **THEN** the second run reports `changed=0`
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: A second run changes nothing")

#### Scenario: A checksum mismatch fails the play before the env is touched
- **WHEN** the artifact's sha256 differs from `life_manager_proton_sha256` and the play runs the proton tasks followed by `config.yml`
- **THEN** the play fails, no file exists at `life_manager_proton_bin` and the env file was not written or changed
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: A checksum mismatch fails the play before the env is touched")

#### Scenario: The flag off downloads and removes nothing
- **WHEN** the role's `main.yml` ordering runs with `life_manager_proton_enabled: false` and a file already at `life_manager_proton_bin`
- **THEN** no download is attempted (the unreachable URL is never requested), that file is unchanged and no `.config` directory is created
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: The flag off downloads and removes nothing")

#### Scenario: A non-x86_64 host fails with a message naming the architecture
- **WHEN** the flag is on and `ansible_architecture` is `aarch64`
- **THEN** the play fails before any download and the failure message contains `aarch64` (the assert carries no `no_log`)
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: A non-x86_64 host fails with a message naming the architecture")

#### Scenario: The real download verifies on life-manager01
- **WHEN** the merged change deploys to life-manager01 for the first time
- **THEN** `/usr/local/bin/proton` exists, `proton --version` reports v5.1.0 and the deploy run is green
- **proof:** manual (needs the real GitHub release asset and the live host; offline fixtures serve a local file)

### Requirement: The service environment carries the Proton variables behind the flag

With the flag on, `templates/env.j2` SHALL add `PROTON_CLI={{ life_manager_proton_bin }}`, `PROTON_PROFILE={{ life_manager_proton_profile }}` (default `default`) and `XDG_CONFIG_HOME={{ life_manager_data_dir }}/.config`. With the flag off, the rendered env file SHALL be byte-identical to the file rendered before this change. The existing `Restart life-manager` handler SHALL fire when the env changes.

#### Scenario: The flag on adds exactly the three Proton lines
- **WHEN** `env.j2` renders with the flag on and defaults
- **THEN** the file is the flag-off content plus `PROTON_CLI=/usr/local/bin/proton`, `PROTON_PROFILE=default` and `XDG_CONFIG_HOME=/var/lib/life-manager/.config`
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: The flag on adds exactly the three Proton lines")

#### Scenario: The flag off renders today's file byte for byte
- **WHEN** `env.j2` renders with the flag off
- **THEN** the output equals the pre-change content (the literal six lines HOST, PORT, NODE_ENV, DATABASE_PATH, PROTOCOL_HEADER under the managed header), with no blank trailing line added
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: The flag off renders today's file byte for byte")

#### Scenario: An env change restarts the service once
- **WHEN** `config.yml` runs against a host whose env lacks the Proton lines, then runs again
- **THEN** the `Restart life-manager` handler fires exactly once in the first run and not in the second
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: An env change restarts the service once")

### Requirement: The Proton session directory exists with owner-only access

With the flag on, the role SHALL ensure `{{ life_manager_data_dir }}/.config` and `{{ life_manager_data_dir }}/.config/proton-cli` exist, owned by `life_manager_user:life_manager_group`, mode `0700`. Existing contents SHALL NOT be touched.

#### Scenario: The session directories are created owner-only
- **WHEN** the proton tasks run with the flag on and the directories absent
- **THEN** both directories exist with mode `0700` and the configured owner and group
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: The session directories are created owner-only")

#### Scenario: An existing session survives a run
- **WHEN** `.config/proton-cli/sessions/default.json` exists and the proton tasks run again
- **THEN** the file content is unchanged and the run reports no change for the directories
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: An existing session survives a run")

### Requirement: A missing Proton login is reported, never fixed or failed on

With the flag on, the role SHALL check with `ansible.builtin.stat` (no `proton` call, no network) for `{{ life_manager_data_dir }}/.config/proton-cli/sessions/{{ life_manager_proton_profile }}.json`. If it is missing, the play SHALL print a message naming the exact command `sudo -u life-manager env XDG_CONFIG_HOME=/var/lib/life-manager/.config /usr/local/bin/proton account login --profile default` (rendered from the role variables). The check SHALL NOT fail the play and SHALL NOT sit inside the smoke-check/rollback path of `verify.yml`.

#### Scenario: A missing session prints the login command and the play succeeds
- **WHEN** the proton tasks run with the flag on and no session file, with a stub `proton` on PATH
- **THEN** the play exits 0, its output contains `Proton login needed` and the exact command above, and the stub logged zero calls
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: A missing session prints the login command and the play succeeds")

#### Scenario: A present session prints no warning
- **WHEN** the session file exists
- **THEN** the output does not contain `Proton login needed`
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: A present session prints no warning")

#### Scenario: Check mode still reports the missing session
- **WHEN** the proton tasks run under `--check` with no session file
- **THEN** the stat task runs and the output contains `Proton login needed`
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: Check mode still reports the missing session")

#### Scenario: The session check cannot fail the play or trigger a rollback
- **WHEN** `tasks/main.yml`, `tasks/proton.yml` and `tasks/verify.yml` are parsed
- **THEN** the session-check tasks carry no `fail`, `failed_when` or `assert` and are not inside the `block`/`rescue` of `verify.yml`; `verify.yml` does not mention Proton
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: The session check cannot fail the play or trigger a rollback")

#### Scenario: The warning shows in the real deploy log
- **WHEN** the first deploy with the flag runs on runner01 before anyone has logged in
- **THEN** the deploy log of `life-manager.yml` shows `Proton login needed` with the command, and the run is green
- **proof:** manual (needs the runner's real log and a host without a session)

### Requirement: life-manager01 enables Proton and the role documents the login

`ansible/inventory/host_vars/life-manager01/vars.yml` SHALL set `life_manager_proton_enabled: true`. The role README SHALL document the Proton variables, the one-time login command, re-login after a CAPTCHA or expired session (no Ansible run needed), and that the session is not covered by `sqlite_backups`, so a rebuild needs a re-login.

#### Scenario: life-manager01 enables the flag
- **WHEN** `host_vars/life-manager01/vars.yml` is parsed
- **THEN** `life_manager_proton_enabled` is boolean `true`
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: life-manager01 enables the flag")

#### Scenario: The README holds the variables and the login runbook
- **WHEN** `ansible/roles/life_manager/README.md` is read
- **THEN** it names `life_manager_proton_enabled`, `_version`, `_url`, `_sha256`, `_bin` and `_profile`, the exact login command, a re-login section and the statement that the session is not backed up
- **proof:** unit (scripts/tests/life-manager-proton.sh: "Scenario: The README holds the variables and the login runbook")

#### Scenario: Login and sync work end to end
- **WHEN** Rue runs the reported login command on life-manager01, re-runs the deploy, then opens `/sync` and presses "Sync now"
- **THEN** the re-run shows no login warning and the events appear in Proton Calendar
- **proof:** manual (real Proton account, CAPTCHA and TOTP; cannot be automated, see Non-Goals)

### Requirement: The fixture test runs in proof for every file it covers

`scripts/proof.sh` SHALL run `scripts/tests/life-manager-proton.sh` as the sensor `life-manager-proton fixtures` (violation `LIFE_MANAGER_PROTON_FIXTURES_FAILED`) when a staged file is under `ansible/roles/life_manager/`, under `ansible/inventory/host_vars/life-manager01/`, or is the test itself, and always under `--all`.

#### Scenario: Changing the role triggers the fixtures
- **WHEN** `scripts/proof.sh --all` runs
- **THEN** the output contains `PASS: life-manager-proton fixtures`, and the proof.sh case patterns include the three paths above
- **proof:** unit (scripts/proof.sh --all: `PASS: life-manager-proton fixtures`; ansible-lint and the `life-manager.yml` syntax check pass in the same run)
