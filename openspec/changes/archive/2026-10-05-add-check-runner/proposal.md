## Why

The merge verdict for `main` (`ci.yml` → `proof`) runs on GitHub-hosted
`ubuntu-24.04`, so the repo's gate depends on GitHub's runner fleet, minutes and
tool-install time. A second self-hosted runner, isolated from the homelab and
holding no secrets, moves the execution of `scripts/proof.sh --all` onto the
homelab while keeping the deploy runner (`runner01`) untouched and unreachable
from PR code.

## What Changes

- New LXC `check01` declared in `hosts.auto.tfvars` (group `check_runner`),
  configured by a new `ansible/roles/check_runner` role and a human-run
  playbook next to `deploy_runner.yml` (outside the services directory, so a
  deploy never selects it).
- The runner registers on this repo only, with the label `homelab-check`. It
  runs unprivileged without sudo, wipes `_work` before each job, holds no
  deploy key, vault password, Terraform environment or any other credential.
- Its egress is restricted by the existing `egress_firewall` role with an
  empty SSH list and no API targets: DNS and TCP 80/443 to non-private
  addresses only. Guests, the Proxmox node and `runner01` are unreachable.
- `ci.yml`: the `proof` job moves to `runs-on: [self-hosted, homelab-check]`.
  Tools (Terraform, tflint, ansible-core, ansible-lint, checkov, collections)
  are pinned on the runner and no longer installed per job. `security-baseline`
  stays on its GitHub-hosted reusable workflow (out of scope).
- `scripts/checks/workflow-triggers.py` changes from "no `self-hosted` with an
  untrusted trigger" to an allow-list: under an untrusted trigger a job may
  request a self-hosted runner only when its labels are exactly `self-hosted`
  plus `homelab-check`. `homelab-deploy`, any other self-hosted label and any
  `${{ }}` expression still fail. Fixture tests are added and wired into
  `proof.sh`.
- **BREAKING (spec):** `ci-pipeline` no longer says every `ci.yml` job runs on
  a GitHub-hosted runner, and its self-hosted rule becomes the allow-list.
- Docs: `docs/check-runner.md` (setup, day 2, how to fall back to a hosted
  runner when `check01` is down).

## Capabilities

### New Capabilities
- `check-runner`: the isolated, secret-free self-hosted runner for CI checks. Covers declaration, registration scope and label, unprivileged operation, egress restriction, pinned toolchain and the fallback.

### Modified Capabilities
- `ci-pipeline`: the `proof` job runs on the check runner instead of a GitHub-hosted one, and the "self-hosted runners are unreachable from untrusted events" requirement becomes a label allow-list (`homelab-check` allowed, everything else still refused).

## Impact

- `.github/workflows/ci.yml`, `scripts/checks/workflow-triggers.py`,
  `scripts/proof.sh`, new `scripts/tests/workflow-triggers.sh`.
- `terraform/environments/homelab/hosts.auto.tfvars` (new guest; applied by
  the existing `deploy` workflow after approval).
- `ansible/roles/check_runner` (new), a new base-configuration playbook,
  `ansible/inventory/group_vars/check_runner`.
- `docs/check-runner.md`; `docs/deploy-runner.md` gets a pointer.
- GitHub settings (manual): register the runner, keep fork-PR approval for all
  outside contributors, required check name `proof` unchanged.
- Risk accepted: a PR can still falsify the verdict by editing what runs on
  `check01`. The runner cannot reach anything worth taking, so the damage is a
  wrong green check, and the same PR is reviewed by Rue before merge.

## Non-Goals

- Moving `security-baseline` (shared `Rue-Asha/ci` workflow) off GitHub.
- Ephemeral per-job runners: they need a registration credential on the box
  (PAT, GitHub App or JIT config), which contradicts "holds no secrets". See
  design for what that would buy.
- A VLAN or separate bridge. Isolation is host-level nftables in v1.
- Letting `check01` run the deploy workflow, or `runner01` run CI.
- Replacing the local `.githooks/pre-commit` gate.
- Reducing GitHub dependence for PRs, branch protection or the deploy workflow.

## Appetite

One evening for the code and docs; the live setup (apply, register, flip
`ci.yml`) is a second short sitting.

## Done criteria

- [ ] `check01` appears in `hosts.auto.tfvars`; `terraform fmt -check`, `validate`, `tflint`, `checkov` pass.
- [ ] `check_runner` playbook passes `--syntax-check` and `ansible-lint`; no deploy playbook selects it.
- [ ] `scripts/tests/workflow-triggers.sh` passes and runs from `proof.sh` when the check or its test changes.
- [ ] A workflow with `on: pull_request` and `runs-on: [self-hosted, homelab-deploy]` fails the proof; with `[self-hosted, homelab-check]` it passes.
- [ ] `ci.yml` `proof` runs on `check01`, is green on a PR, and `proof` is still the required check name.
- [ ] From `check01` as the runner user: `ssh` to a guest, to `proxmox1` and to `runner01` fail, `curl -I https://github.com` succeeds, `sudo -n true` fails.
- [ ] No Actions or environment secrets exist on the repo; `check01` holds no key authorised anywhere.
- [ ] `docs/check-runner.md` explains the fallback to `ubuntu-24.04`.
