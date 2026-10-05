## 1. Trigger rule

- [x] 1.1 Change `scripts/checks/workflow-triggers.py` to the allow-list in design D6
- [x] 1.2 Add `scripts/tests/workflow-triggers.sh` with fixtures for the five scenarios under "Self-hosted runners are unreachable from untrusted events" plus a trusted-trigger case (`push` with `homelab-deploy` passes)
- [x] 1.3 Wire the test into `scripts/proof.sh` (run when the check or its test changes), as `deploy-targets` is
- [x] 1.4 Update the docstring and `SELF_HOSTED_ON_UNTRUSTED_TRIGGER` message in the check

## 2. Guest

- [x] 2.1 Add `check01` (vmid 226, `192.168.0.226/24`, group `check_runner`, tags `ci`, `terraform`, 2 cores, 2048 MiB, 12 GB) to `terraform/environments/homelab/hosts.auto.tfvars` with a comment like `runner01`'s
- [x] 2.2 `terraform fmt -check -recursive`, `validate`, `tflint`, `checkov` green

## 3. Role and playbook

- [x] 3.1 Create `ansible/roles/check_runner` with `tasks/main.yml` as an import hub: `user.yml`, `install.yml`, `toolchain.yml`, `register.yml`, `environment.yml`, `service.yml`; defaults with `check_runner_` prefix, label `homelab-check`, repo URL, runner version and sha256
- [x] 3.2 `toolchain.yml`: root-owned Terraform, tflint, and a root-owned venv with the pins from `ci/requirements.txt`; no credentials
- [x] 3.3 `register.yml`: registration token via `-e`, never stored; `--disableupdate`; wipe `_work` before each job (`ACTIONS_RUNNER_HOOK_JOB_STARTED` script in the unit's environment)
- [x] 3.4 Systemd unit with `NoNewPrivileges`, no sudo for the runner user
- [x] 3.5 Playbook in the base-configuration directory: `common`, `egress_firewall` (empty SSH and API targets), `check_runner` on `check_runner`
- [x] 3.6 `ansible/inventory/group_vars/check_runner`: remove the deploy public key from `check01` as `group_vars/github_runner` does for `runner01`
- [x] 3.7 Add a `proof.sh` sensor "check runner role has no deploy credentials" (`git grep` for `deploy_ed25519|vault_pass|terraform.env` under the role)
- [x] 3.8 Add a `deploy-targets` fixture proving the new role/playbook selects no services playbook; run `scripts/tests/deploy-targets.sh`
- [x] 3.9 `ansible-playbook --syntax-check` and `ansible-lint` green

## 4. Docs

- [x] 4.1 `docs/check-runner.md`: what it holds (nothing), setup order, boundary checks, version bumps, fallback to `ubuntu-24.04` (D7)
- [x] 4.2 Pointer from `docs/deploy-runner.md`; update `.claude/CLAUDE.md` runner notes only if repo owner asks

## 5. Live rollout (separate PR and sitting, needs Rue)

- [x] 5.1 Merge steps 1-4; approve the `infrastructure` apply that creates `check01`
- [x] 5.2 Run bootstrap against `check01`, then the check-runner playbook with a registration token (manual)
- [x] 5.3 Verify the boundary scenarios from the check-runner spec by hand
- [x] 5.4 Confirm fork-PR approval setting for all outside contributors
- [x] 5.5 PR flipping `ci.yml` `proof` to `[self-hosted, homelab-check]`, dropping per-job tool setup; it must go green on `check01` before merge
