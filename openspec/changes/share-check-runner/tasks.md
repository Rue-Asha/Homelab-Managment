## 1. Guest resources

> unit: depends=none · files=terraform/environments/homelab/hosts.auto.tfvars

- [x] 1.1 Raise `check01` to 4 cores, 16384 MiB memory, 32 GB disk (D11); update its comment to "shared check host, one runner per repo in `check_runner_repos`"
- [x] 1.2 `terraform fmt -check -recursive`, `validate`, `tflint`, `checkov` green

## 2. Role: per-repo instances

> unit: depends=none · files=ansible/roles/check_runner/**, ansible/inventory/group_vars/check_runner/vars.yml, ansible/playbooks/01_BASE_CONFIGURATION/check_runner.yml, scripts/proof.sh

- [x] 2.1 Defaults: drop the scalar `check_runner_user`/`_home`/`_dir`/`_service_name`/`_repo_url`/`_registration_token`; add `check_runner_repos: []` and `check_runner_browser_packages` (D9: capture the list from `npx playwright install-deps --dry-run chromium` for Debian 13)
- [x] 2.2 `group_vars/check_runner/vars.yml`: `check_runner_repos` with `Rue-Asha/Homelab-Managment`, `Rue-Asha/Life-Manager`, `Rue-Asha/Rues-Arcade`
- [x] 2.3 New `preflight.yml` (first import): assert no duplicate slugs ("Scenario: Two entries would share an instance"); read each repo's fork-PR approval policy via `gh api` on localhost (`check_mode: false`, `changed_when: false`) and assert `all_external_contributors`, `fail_msg` naming the repo, no `no_log` (D5)
- [x] 2.4 New `legacy.yml`: stop and disable `check-runner.service`, remove its unit file, remove user `check-runner` with its home (D8)
- [x] 2.5 `user.yml`, `install.yml`: loop over `check_runner_repos`, creating user `check-runner-<slug>` and home `0700`, no sudoers entry, runner unpacked per instance. Download the release archive once to a root-owned path and unpack it into each instance
- [x] 2.6 `toolchain.yml`: add `check_runner_browser_packages` to the apt install; Terraform, tflint and venv unchanged
- [x] 2.7 `register.yml`: per instance, stat `.runner`; for the unregistered ones mint a token with `gh api -X POST …/registration-token` (`delegate_to: localhost`, `become: false`, `no_log: true`, skipped in check mode) and run `config.sh` with name `<host>-<slug>` and label `homelab-check` (D4)
- [x] 2.8 `environment.yml`: per-instance hook `/usr/local/lib/check-runner/<slug>-job-started.sh` emptying that instance's workspace, plus a per-instance `.env` and `.path` (D6)
- [x] 2.9 `service.yml`: a templated unit per instance (`check-runner-<slug>.service`, `NoNewPrivileges`); a handler restarts only the instance that changed; `find` unit files of slugs no longer listed and stop and disable them (D7)
- [x] 2.10 Update the playbook header (no `-e` token anymore; prerequisite `gh auth status`) and the role README variable table
- [x] 2.11 Keep the `proof.sh` sensor "check runner role has no deploy credentials" green, and check that no new file under the role matches it
- [x] 2.12 `ansible-playbook --syntax-check` and `ansible-lint` green; `scripts/proof.sh --all` green

## 3. Docs

> unit: depends=2 · files=docs/check-runner.md, docs/deploy-runner.md

- [x] 3.1 `docs/check-runner.md`: shared-host model and why it isn't an org (D1); prerequisites (`gh` admin login, fork approval); "Add a repo" runbook; "Remove a repo" runbook (list entry, re-run, `gh api -X DELETE` the registration, `userdel -r`)
- [x] 3.2 Extend "When `check01` is down" to every listed repo, with the one-line fallback per repo (`ci.yml` caller input → `["ubuntu-24.04"]` for app repos)
- [x] 3.3 Update the boundary-check section with the cross-instance check ("Scenario: A job reads another repo's runner")
- [x] 3.4 Update the pointer in `docs/deploy-runner.md` if its wording mentions "this repository only"

## 4. Live rollout on check01 (needs Rue)

> unit: depends=1,2,3 · files=none (live system)

- [ ] 4.1 Merge groups 1-3; approve the `infrastructure` apply that resizes `check01` ⚠ irreversible
- [ ] 4.2 Set fork-PR approval to "all external contributors" on `Life-Manager`, `Rues-Arcade`, and confirm on `Homelab-Managment` (GitHub settings, by hand)
- [ ] 4.3 `ansible-playbook … check_runner.yml --check --diff`, then the real run; legacy instance removed, three instances online ⚠ irreversible (removes the old runner user)
- [ ] 4.4 Delete the offline legacy `check01` runner from `Homelab-Managment` (`gh api -X DELETE`) ⚠ irreversible
- [ ] 4.5 Re-run the playbook: no token minted, no changes
- [ ] 4.6 Verify the manual spec scenarios: deploy label never lands, `sudo -n true` fails, cross-instance `ls` fails, no token on disk, egress unchanged
- [ ] 4.7 Open a no-op PR on `Homelab-Managment`; `proof` goes green on `check01-homelab-managment`

## 5. App repos (separate PRs in Life-Manager and Rues-Arcade)

> unit: depends=4 · files=(other repos) .github/workflows/gate.yml, ci.yml, release.yml

- [ ] 5.1 Read each repo's ruleset to find the current required check name (Open Question 2)
- [ ] 5.2 `Life-Manager`: move the `ci` job body into `gate.yml` (`workflow_call`, input `runner`, `runs-on: ${{ fromJSON(inputs.runner) }}`) and drop `--with-deps` from its Playwright install; `ci.yml` calls the gate with `["self-hosted","homelab-check"]`; `release.yml` calls it with `["ubuntu-24.04"]` (D10)
- [ ] 5.3 Same for `Rues-Arcade`
- [ ] 5.4 Each PR goes green on `check01`; update the ruleset's required check name in the same sitting ⚠ irreversible (branch protection change)
- [ ] 5.5 Push a release tag in one app repo and confirm the release jobs ran on `ubuntu-24.04` ("Scenario: A release tag is pushed") ⚠ irreversible (publishes a release)
