## Why

`check01` serves `Homelab-Managment` only. The other repos that deploy to the
homelab (`Life-Manager`, `Rues-Arcade`) still run their checks on GitHub-hosted
`ubuntu-24.04`. Doing the same for each of them would mean another host, role
and token dance per repo. `Rue-Asha` is a personal account, not an
organisation, so GitHub offers no account-wide runner or runner group: a
self-hosted runner always belongs to exactly one repository. Registration per
repo can't be avoided, so it has to be automated. One host, one role and one
list should cover every repo, and adding a repo should take one list entry and
one playbook run.

## What Changes

- `check01` becomes the shared check host. The `check_runner` role takes a list
  `check_runner_repos` and runs **one runner instance per repo**, each under its
  own unix user, directory and systemd unit. A PR in one repo can't reach
  another repo's workspace, tool cache or runner credentials.
- Every instance registers with the same label `homelab-check`. Repository
  runners are only visible to their own repo, so the label needs no per-repo
  variant, and every repo's workflows request `[self-hosted, homelab-check]`.
- Registration tokens come from the operator's workstation, not from `-e`. While
  the playbook runs, `gh api` mints a one-hour token on `localhost` for each
  repo whose instance isn't registered yet and passes it to `config.sh`. Nothing
  is stored on `check01`, and the box still holds no credential of its own.
- Fail-closed precondition: before registering, the playbook reads each repo's
  fork-PR approval policy (`gh api`, read-only) and stops if it isn't
  "all external contributors". All these repos are public.
- The host toolchain grows by what the Node repos can't install without sudo:
  the system libraries headless Chromium needs for Playwright, as a pinned apt
  list. Node itself still comes from `actions/setup-node` per job, into the
  instance's own tool cache.
- `check01` gets more cores, memory and disk in `hosts.auto.tfvars`, because
  several instances can run jobs at the same time and Playwright e2e is heavier
  than `proof.sh`.
- The existing single instance (`check-runner` user and unit) is migrated into
  the list layout as the `Homelab-Managment` entry. The old GitHub registration
  is removed once.
- Follow-up PRs in `Life-Manager` and `Rues-Arcade` (outside this repo) move
  their PR checks to `[self-hosted, homelab-check]`. **Release builds stay on
  GitHub-hosted runners:** a tarball that gets deployed must not be built on a
  box that runs PR code.
- `docs/check-runner.md` gains "Add a repo" and "Remove a repo" runbooks, and
  its fallback section is extended to the other repos.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `check-runner`: changes from "serves this repository only" to "one isolated
  instance per listed repository on a shared host". Adds token minting from the
  workstation, the fork-approval precondition, per-instance isolation and the
  Playwright system dependencies. The no-credentials, egress and root-owned
  toolchain requirements stay as they are.

## Impact

- `ansible/roles/check_runner/` (defaults, all task files, templates, README),
  `ansible/playbooks/01_BASE_CONFIGURATION/check_runner.yml`,
  `ansible/inventory/group_vars/check_runner/vars.yml`.
- `terraform/environments/homelab/hosts.auto.tfvars` (resources for `check01`;
  the existing `deploy` workflow plans and applies it after approval).
- `docs/check-runner.md`.
- Workstation prerequisite: `gh` authenticated with admin rights on every listed
  repo (needed to mint registration tokens).
- Other repos: one PR each in `Life-Manager` and `Rues-Arcade` that splits the
  PR check from the release build and moves only the check.
- GitHub settings (manual, per repo): fork-PR approval set to all external
  contributors. The playbook verifies this but never changes it.

## Non-Goals

- Moving the repos into a GitHub organisation. That would give real
  account-wide runner groups, but it changes every URL and breaks the
  `Rue-Asha.github.io` user Pages site.
- Ephemeral or JIT runners through a GitHub App. That gives a clean box per job,
  but needs an App key and a controller in the homelab.
- Moving release builds, `security-baseline` (`Rue-Asha/ci`) or the deploy
  workflow off GitHub-hosted runners or `runner01`.
- `Rue-Asha.github.io` and `Party-Games`. They have no PR check job beyond the
  shared security baseline today. Adding them later is one list entry.
- Per-repo toolchains baked into the host beyond the Playwright system
  libraries. Node versions stay per repo via `setup-node`.
- Changing `workflow-triggers.py`. `runner01` is only registered on this repo,
  so no other repo's workflow can reach it.

## Appetite

One evening for the role, docs and Terraform bump. The live migration and the
two app-repo PRs are a second short sitting.

## Done criteria

- [ ] `check_runner` playbook passes `--syntax-check`, `ansible-lint` and a `--check` run against `check01`.
- [ ] With `check_runner_repos` listing three repos, `check01` runs three `check-runner-*` units under three different users, and `systemctl status` shows each as active.
- [ ] Each repo's Settings → Actions → Runners shows exactly one online runner with the label `homelab-check`, and the old single `check01` registration is gone.
- [ ] Running the playbook a second time mints no token and reports no change.
- [ ] A repo whose fork-PR approval isn't "all external contributors" makes the playbook fail before any registration.
- [ ] Logged in as one instance's user, reading another instance's home directory fails.
- [ ] `proof` on a `Homelab-Managment` PR, and the PR check on a `Life-Manager` and a `Rues-Arcade` PR, all go green on `check01`. Their release workflows still use `ubuntu-24.04`.
- [ ] `rg -n 'vault_pass|deploy_ed25519|terraform.env' ansible/roles/check_runner` finds nothing, and no token file exists on `check01`.
- [ ] `docs/check-runner.md` has the add-repo runbook, the remove-repo runbook and a fallback that covers every listed repo.
