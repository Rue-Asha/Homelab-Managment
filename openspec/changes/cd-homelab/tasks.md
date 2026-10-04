## 1. Prerequisites

- [x] 1.1 Merge `feat/life-manager-release-artifact` to `main` and cut `feat/cd-homelab` from the updated `main`
- [x] 1.2 Pin every collection in `ansible/collections/requirements.yml` to an exact version (the ones currently installed)
- [x] 1.3 Add a `proof.sh` sensor that fails on a non-exact collection version; prove it red with a `>=` range, then green

## 2. Trigger guard in proof

- [x] 2.1 Add a `proof.sh` sensor that fails any `.github/workflows/*.yml` whose `on:` includes `pull_request`, `pull_request_target`, `issues`, `issue_comment`, `discussion*`, `fork`, `watch` or `workflow_run` and whose jobs request `self-hosted`
- [x] 2.2 Prove the sensor: a fixture workflow with `pull_request` + `runs-on: [self-hosted, homelab-deploy]` is red with a violation naming it; `ci.yml` stays green

## 3. Change-to-playbook mapping

- [x] 3.1 Write `scripts/deploy-targets.sh` (`<before> <after>` | `--all` | `<playbook>`) per design D5: roles incl. transitive `meta` deps, hosts via `--list-hosts`, groups via `ansible-inventory --graph`, global files → all, zero/non-ancestor `before` → all, deleted playbooks skipped
- [x] 3.2 Add fixture-based tests run by `proof.sh` covering each spec scenario: version bump → only `life-manager.yml`; `roles/nginx/` change → every playbook using `nginx`; `README.md`/`terraform/` only → empty; zero `before` → all; named playbook and `all`
- [x] 3.3 Confirm `runner01`'s playbook is never emitted, even when `roles/common/` changes

## 4. Smoke check and rollback in `life_manager`

- [x] 4.1 Record the pre-run `current` target as `life_manager_previous_release` before `release.yml` swaps it
- [x] 4.2 Add `tasks/verify.yml` (imported last): `flush_handlers`, then `uri` on `http://127.0.0.1/` with `until` 2xx; retries/delay as role defaults (10 × 3 s)
- [x] 4.3 Add the `rescue`: repoint `current` at the previous release if one exists and differs, restart, then `fail` naming both releases
- [x] 4.4 Document the check, the defaults and the forward-only-migrations caveat in `roles/life_manager/README.md`
- [x] 4.5 Run `life-manager.yml --check` and `ansible-lint`; real-host proof happens in 9.3

## 5. Runner host

- [x] 5.1 Add `runner01` (own vmid/IP, group `github_runner`, unprivileged) to `hosts.auto.tfvars`; `terraform plan` shows only the new container and the inventory file
- [ ] 5.2 **Manual, ask first:** `terraform apply`; commit the regenerated `00-terraform.yml`
- [ ] 5.3 **Manual, ask first:** run `02_BASE_CONFIGURATION/bootstrap.yml` against `runner01`

## 6. Roles for the runner

- [x] 6.1 Create `ansible/roles/egress_firewall` (nftables, output default-drop; allow loopback, established, DNS, TCP 22 to a host list, TCP 443 outside RFC 1918; explicit drop to `proxmox_node`)
- [x] 6.2 Create `ansible/roles/github_runner`: `github-runner` user without sudo, pinned runner release download with checksum verification, systemd service, labels `homelab-deploy`, pinned ansible-core from `ci/requirements.txt`
- [x] 6.3 In `github_runner`: generate the deploy key pair, fetch the public key to the controller, build `known_hosts` via `ssh-keyscan` of `proxmox_guest`, place the vault password file (mode 0600), and write the runner `.env` with the four `ANSIBLE_*` overrides from design D3
- [x] 6.4 Registration only when `github_runner_registration_token` is supplied, with `no_log: true`; idempotent when already registered
- [x] 6.5 Add `ansible/playbooks/02_BASE_CONFIGURATION/deploy_runner.yml` (`common`, `egress_firewall`, `github_runner`)
- [x] 6.6 Extend `guest_bootstrap` to authorise the runner's public key for `ansible` alongside the workstation key, skipped when the key file is absent
- [x] 6.7 `ansible-lint` and `--syntax-check` clean

## 7. Deploy workflow

- [x] 7.1 Write `.github/workflows/deploy.yml` per design D9: `push: main` + `workflow_dispatch` (choice input incl. `all`), `contents: read`, concurrency `deploy-production` without cancel, `runs-on: [self-hosted, homelab-deploy]`, `environment: production`, SHA-pinned checkout with `persist-credentials: false` and `fetch-depth: 0`
- [x] 7.2 Steps: install pinned collections → `deploy-targets.sh` → sequential `ansible-playbook <pb> --limit proxmox_guest`, no `--diff`/`-v`; log "nothing to deploy" for an empty target list; list unrun playbooks on failure
- [x] 7.3 Confirm the security baseline and the new trigger sensor pass on the PR

## 8. Specs, docs, settings

- [x] 8.1 Update `.claude/CLAUDE.md` "Service delivery model" (deploy = merge to `main`, CI-built tarball) and the "Before committing" section (new sensors)
- [x] 8.2 Document the runner (bootstrap, token, key rotation, re-keyscan after recreating a guest) and the manual-deploy fallback in `README.md` or `docs/`
- [x] 8.3 **Outward, ask first:** set fork-PR approval to all external contributors (`gh api -X PUT repos/Rue-Asha/Homelab-Managment/actions/permissions/fork-pr-contributor-approval`)
- [x] 8.4 **Outward, ask first:** create the `production` environment with deployment branch policy `main` only; enable "require branches to be up to date" on the `main` ruleset
- [x] 8.5 Verify no Actions or environment secrets exist (`gh secret list`, `gh secret list --env production`)

## 9. Go live and prove it

- [ ] 9.1 **Manual, ask first:** run `deploy_runner.yml` with a fresh registration token; runner shows `idle` with label `homelab-deploy`
- [ ] 9.2 **Manual, ask first:** re-run `bootstrap.yml` on `proxmox_guest` to authorise the deploy key; from `runner01`, prove SSH to `life-manager01` works and to `proxmox1` is refused, and `curl https://192.168.0.22:8006` fails while `curl https://github.com` succeeds
- [ ] 9.3 Merge the PR; the merge deploys `life-manager.yml` (it touches the role) and goes green with the smoke check passing
- [ ] 9.4 Prove rollback: merge a bump to a broken version (or unreachable port), confirm a red run and `current` back on the previous release, then revert the bump and confirm a green redeploy
- [ ] 9.5 Prove the trust boundary: dispatching `deploy` on a feature branch is rejected by the environment policy
