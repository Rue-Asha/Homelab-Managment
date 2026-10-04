## Why

`ci-homelab` gave `main` a trustworthy merge verdict, and Life-Manager already
ships a tested, checksummed release tarball per tag. Getting either onto a
host still means running `ansible-playbook` by hand from the workstation, so
what is on `main` and what is running drift apart until someone remembers.
Merging to `main` should be the deploy.

## What Changes

- A self-hosted GitHub Actions runner in a new LXC (`runner01`), declared in
  Terraform and configured by Ansible, registered **only** on this repository.
  It runs deploys and nothing else — no tests, no builds.
- A `deploy` workflow that runs on `push` to `main` and on
  `workflow_dispatch`, and on no other trigger. It maps the merged diff to the
  `ansible/playbooks/03_SERVICES/<service>.yml` playbooks it affects and runs
  each one in full against its hosts.
- Service playbooks end with an HTTP smoke check; a failed check repoints the
  service's `current` symlink at the previous release, restarts it, and fails
  the run.
- Runner-side Ansible settings: a dedicated deploy key accepted only by the
  `ansible` user on guests (never by `proxmox1`), a real vault password file
  on the runner, and pinned host keys in place of `host_key_checking = False`.
- Hardening for a self-hosted runner on a public repo: fork-PR workflow
  approval required for all external contributors, deploy logs free of
  secrets and `--diff` output, Ansible collections pinned to exact versions,
  and the runner LXC firewalled to SSH towards guests plus outbound HTTPS.
- **BREAKING** (spec): `ci-pipeline`'s "never reaches the homelab and holds no
  secrets" is narrowed to the CI workflow; the deploy workflow is the one
  sanctioned path to the homelab.

Out of scope: automating `terraform apply` (stays manual), automating
`02_BASE_CONFIGURATION`, and automated version-bump PRs from Life-Manager
releases (bumping `life_manager_version` stays a hand-written PR).

Prerequisite: `feat/life-manager-release-artifact` (deploy the CI-built
release tarball) is merged to `main`.

## Capabilities

### New Capabilities
- `continuous-deployment`: merge-to-`main` deploys — triggers, change-to-playbook
  mapping, serialisation, smoke check and rollback, log hygiene.
- `deploy-runner`: the self-hosted runner host — provisioning, registration
  scope, credentials, host-key pinning, network restrictions.

### Modified Capabilities
- `ci-pipeline`: "CI never reaches the homelab and holds no secrets" is scoped
  to `ci.yml`, and a new requirement forbids self-hosted runners in any job
  reachable from `pull_request`, `pull_request_target`, `issues`, or
  `issue_comment`.

## Impact

- New: `.github/workflows/deploy.yml`, `scripts/deploy-targets.sh`,
  `ansible/roles/github_runner/`, a playbook for the runner host, a
  `runner01` entry in `hosts.auto.tfvars` (regenerating the inventory).
- Changed: `ansible/roles/life_manager/` (smoke check + rollback),
  `ansible/collections/requirements.yml` (exact pins), guest `authorized_keys`
  for the `ansible` user (adds the deploy key).
- GitHub settings: fork-PR approval policy, a `production` environment.
- Requires one manual `terraform apply` and one manual runner bootstrap; after
  that, every service merge reaches its host without a workstation.
