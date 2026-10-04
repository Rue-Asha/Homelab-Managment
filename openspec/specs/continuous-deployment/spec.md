# continuous-deployment Specification

## Purpose

Merging to `main` deploys: `.github/workflows/deploy.yml` runs on the homelab's
self-hosted runner, applies only the `03_SERVICES` playbooks the merge affects,
never overlaps another deploy, rolls a service back when its smoke check fails,
and keeps its public logs free of secrets. Archived from `cd-homelab`.

## Requirements

### Requirement: Merging to main deploys

`.github/workflows/deploy.yml` SHALL run on `push` to `main` and on
`workflow_dispatch`, and on no other event. Its deploy job SHALL run on the
homelab's self-hosted runner, selected by the `homelab-deploy` label, and SHALL
use the `production` environment, whose deployment branch policy allows only
`main`.

#### Scenario: A service change is merged
- **WHEN** a PR changing `ansible/inventory/host_vars/life-manager01/vars.yml` is merged to `main`
- **THEN** a `deploy` run starts on the self-hosted runner and appears as a deployment to `production`

#### Scenario: Dispatch from a feature branch
- **WHEN** `deploy` is dispatched with a ref other than `main`
- **THEN** GitHub rejects the job before it reaches the runner, because the `production` environment only allows `main`

### Requirement: Each service is deployed by its own 03_SERVICES playbook

The deploy SHALL run exactly the playbooks under
`ansible/playbooks/03_SERVICES/` that the pushed commits affect, each in full
(no `--tags`), against the hosts the playbook targets. A playbook is affected
when the diff between the push's `before` and `after` commits touches:
the playbook file; any file under `ansible/roles/<role>/` for a role the
playbook applies; `ansible/inventory/host_vars/<host>/` for a host it targets;
`ansible/inventory/group_vars/<group>` for a group containing a host it
targets; or `ansible/ansible.cfg` or `ansible/collections/requirements.yml`,
which affect every playbook. Playbooks outside `03_SERVICES` SHALL NOT be run
by the deploy. The change-to-playbook mapping SHALL live in a script that can
be run locally with the same inputs.

#### Scenario: Version bump for one service
- **WHEN** a merge changes only `life_manager_version` in `host_vars/life-manager01/vars.yml`
- **THEN** only `03_SERVICES/life-manager.yml` runs

#### Scenario: Shared role changes
- **WHEN** a merge changes a file under `ansible/roles/nginx/`
- **THEN** every `03_SERVICES` playbook that applies the `nginx` role runs

#### Scenario: Nothing deployable changed
- **WHEN** a merge changes only `README.md` or files under `terraform/`
- **THEN** the deploy run succeeds without running any playbook and says so in its log

#### Scenario: Push history cannot be diffed
- **WHEN** the push's `before` commit is all zeros or not an ancestor of `after`
- **THEN** every `03_SERVICES` playbook runs

#### Scenario: Manual redeploy
- **WHEN** `deploy` is dispatched with a playbook name, or with `all`
- **THEN** that playbook, or every `03_SERVICES` playbook, runs regardless of the diff

### Requirement: Deploys never overlap

All `deploy` runs SHALL share one concurrency group with
`cancel-in-progress: false`, so a second merge waits for the running deploy to
finish instead of interrupting it.

#### Scenario: Two merges in quick succession
- **WHEN** a second PR is merged while the first merge's deploy is running
- **THEN** the second deploy starts only after the first has finished

### Requirement: A failed smoke check rolls the service back

A service role that deploys releases SHALL, after its handlers have run,
request the service through its reverse proxy on the host and require an HTTP
success status within a bounded number of retries. If the check fails, the
role SHALL point `current` back at the release that was active before the run,
restart the service, and fail the play. If no previous release exists, it SHALL
fail without rolling back. The check SHALL also run on manual playbook runs.

#### Scenario: The new release does not come up
- **WHEN** the deployed release exits on start, so the proxy returns 502
- **THEN** `current` points at the previous release again, the service is running it, and the deploy run is red

#### Scenario: The new release is healthy
- **WHEN** the proxy returns 200 within the retry window
- **THEN** `current` points at the new release and the deploy run is green

#### Scenario: Nothing was redeployed
- **WHEN** the playbook runs with the release already active
- **THEN** the smoke check still runs and no rollback is attempted on success

### Requirement: Deploy logs are safe to publish

The deploy SHALL NOT run Ansible with `--diff` or with verbosity above the
default, and every task that renders, reads, or registers a secret value SHALL
set `no_log: true`, because the repository is public and its Actions logs are
world-readable.

#### Scenario: Deploy workflow is inspected
- **WHEN** `deploy.yml` is inspected
- **THEN** no `ansible-playbook` invocation contains `--diff` or `-v`

### Requirement: Ansible dependencies are pinned for deploys

`ansible/collections/requirements.yml` SHALL pin every collection to an exact
version, so a deploy installs the same collection code that CI linted.

#### Scenario: A range is introduced
- **WHEN** a collection is listed as `version: ">=8.0.0"`
- **THEN** the proof fails the change
