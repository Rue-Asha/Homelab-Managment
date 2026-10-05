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
`ansible/playbooks/03_SERVICES/` that the pushed commits affect or that target
a guest the same run's `apply` job created, each in full (no `--tags`), against
the hosts the playbook targets. A playbook is affected when the diff between the
push's `before` and `after` commits touches:
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
- **proof:** unit ("version bump runs only its service")

#### Scenario: Shared role changes
- **WHEN** a merge changes a file under `ansible/roles/nginx/`
- **THEN** every `03_SERVICES` playbook that applies the `nginx` role runs
- **proof:** unit ("shared role runs every playbook using it, incl. via meta deps")

#### Scenario: Nothing deployable changed
- **WHEN** a merge changes only `README.md` or files under `terraform/` and creates no guest
- **THEN** the deploy run succeeds without running any playbook and says so in its log
- **proof:** unit ("README and terraform deploy nothing")

#### Scenario: Push history cannot be diffed
- **WHEN** the push's `before` commit is all zeros or not an ancestor of `after`
- **THEN** every `03_SERVICES` playbook runs
- **proof:** unit ("zero before runs everything", "non-ancestor before runs everything")

#### Scenario: Manual redeploy
- **WHEN** `deploy` is dispatched with a playbook name, or with `all`
- **THEN** that playbook, or every `03_SERVICES` playbook, runs regardless of the diff and of any guest the run's `apply` created
- **proof:** unit ("named playbook", "--all"); manual (dispatch wiring needs the live runner)

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

### Requirement: Infrastructure applies before services deploy

`.github/workflows/deploy.yml` SHALL order its jobs `plan`, `apply`, `deploy`
within one workflow and one concurrency group, so an infrastructure change and a
service change in the same push never run concurrently, and `deploy` starts only
after `apply` succeeded or was skipped. A failed or rejected `apply` SHALL stop
`deploy`.

#### Scenario: A push changes only a service
- **WHEN** a merge touches no file under `terraform/`
- **THEN** `plan` and `apply` are skipped and `deploy` runs
- **proof:** manual (needs a real run)

#### Scenario: A push changes a host and its service
- **WHEN** a merge adds a guest in `hosts.auto.tfvars` and its service playbook inputs
- **THEN** `deploy` starts only after the `apply` job is approved and succeeds
- **proof:** manual (needs a real run)

#### Scenario: The apply is rejected
- **WHEN** the `infrastructure` approval is rejected
- **THEN** no `deploy` job runs for that push
- **proof:** manual (needs a real run)

### Requirement: The apply job hands the guests it created to the deploy

`scripts/tf-ci.sh apply` SHALL report the guests the applied plan created — the
same set whose host keys it pins — as the `apply` job output `created`, a
space-separated list of host names that is empty when no guest was created. On
`push`, the `deploy` job SHALL pass that list to `scripts/deploy-targets.sh`.
When `apply` is skipped, the list SHALL be empty. A failed or rejected `apply`
SHALL still stop `deploy`.

#### Scenario: A merge adds a guest
- **WHEN** a merge adds `pihole01` to `hosts.auto.tfvars` and the approved `apply` creates it
- **THEN** the `apply` job's `created` output is `pihole01`, and the `deploy` job of the same run passes it to `deploy-targets.sh` and runs `03_SERVICES/pihole.yml`, ending with its smoke check
- **proof:** manual (first live run: rebuild-pihole01)

#### Scenario: No terraform change
- **WHEN** a merge touches no file under `terraform/`
- **THEN** `apply` is skipped, `created` is empty, and `deploy` selects exactly the playbooks the `ansible/` diff selects
- **proof:** manual (this change's own merge run, Done criterion 2)

#### Scenario: Apply creates nothing
- **WHEN** the applied plan only updates or destroys guests
- **THEN** `created` is empty and `deploy` selects exactly the playbooks the `ansible/` diff selects
- **proof:** manual (needs a live update-only apply on the runner)

#### Scenario: Apply fails
- **WHEN** `apply` fails, including when a created guest's host key cannot be pinned
- **THEN** no `deploy` job runs for that push
- **proof:** manual (needs a live failed apply; the job condition is unchanged)

### Requirement: A created guest selects its service playbooks

`scripts/deploy-targets.sh` SHALL accept the created guests as
`--created "<host> ..."` in front of `<before> <after>` and treat each like a
changed host: every `03_SERVICES` playbook whose `--list-hosts` contains it is
selected, merged with the playbooks the diff selects, each printed once, in the
existing sorted order. An empty list SHALL give the same output as no
`--created`. A created host that no `03_SERVICES` playbook targets SHALL be
reported on stderr and select nothing. A created host that is not in the
rendered inventory SHALL fail the script with a message naming it.

#### Scenario: A created guest selects its service playbook
- **WHEN** the diff touches only `terraform/` and `--created pihole01` is passed
- **THEN** the output is exactly `03_SERVICES/pihole.yml`
- **proof:** unit ("Scenario: A created guest selects its service playbook")

#### Scenario: Created guest and diff selections are merged
- **WHEN** the diff changes `host_vars/life-manager01/vars.yml` and `--created pihole01` is passed
- **THEN** the output is `03_SERVICES/life-manager.yml` then `03_SERVICES/pihole.yml`
- **proof:** unit ("Scenario: Created guest and diff selections are merged")

#### Scenario: A playbook selected twice runs once
- **WHEN** the diff changes `host_vars/pihole01/vars.yml` and `--created pihole01` is passed
- **THEN** `03_SERVICES/pihole.yml` appears exactly once
- **proof:** unit ("Scenario: A playbook selected twice runs once")

#### Scenario: A created guest without a service playbook
- **WHEN** `--created` names a guest that no `03_SERVICES` playbook targets
- **THEN** no extra playbook is selected, stderr says `deploy-targets: <host> has no 03_SERVICES playbook`, and the script exits 0
- **proof:** unit ("Scenario: A created guest without a service playbook")

#### Scenario: A created runner is never deployed
- **WHEN** `--created runner01` is passed and `runner01` is in `github_runner`
- **THEN** no playbook is selected for it, in particular not `02_BASE_CONFIGURATION/deploy_runner.yml`
- **proof:** unit ("Scenario: A created runner is never deployed")

#### Scenario: An unknown created host fails loudly
- **WHEN** `--created` names a host that is not in the inventory
- **THEN** the script exits non-zero, prints no playbook, and stderr names the host
- **proof:** unit ("Scenario: An unknown created host fails loudly")

#### Scenario: An empty created list changes nothing
- **WHEN** `--created ""` is passed with a diff that changes `host_vars/life-manager01/vars.yml`
- **THEN** the output is exactly `03_SERVICES/life-manager.yml`, as without `--created`
- **proof:** unit ("Scenario: An empty created list changes nothing")

#### Scenario: Created guests are refused outside the diff form
- **WHEN** `--created pihole01` is passed together with `--all` or a playbook name
- **THEN** the script prints its usage and exits 64
- **proof:** unit ("Scenario: Created guests are refused outside the diff form")

### Requirement: Every guest is declared with an Ansible group

`terraform/environments/homelab/variables.tf` SHALL refuse an `lxc_hosts` entry
whose `groups` is empty, with an error saying that a guest without a group is
unreachable for Ansible, because the rendered inventory places a guest only
under its groups and a created guest missing from it fails the deploy.

#### Scenario: A guest declared without a group is refused at plan
- **WHEN** `hosts.auto.tfvars` declares an LXC host with `groups = []`
- **THEN** `terraform plan` fails on the `lxc_hosts` validation and nothing is applied or deployed
- **proof:** manual (terraform plan with a group-less host; checked locally with a throwaway `terraform test` using a mock provider, not committed)

### Requirement: The created-guest mapping is proven by fixtures

`scripts/tests/deploy-targets.sh` SHALL contain a fixture for every scenario of
"A created guest selects its service playbooks", and `scripts/proof.sh` SHALL
run the fixtures whenever `scripts/deploy-targets.sh` or its tests change and
on `--all`.

#### Scenario: Proof runs the created-guest fixtures
- **WHEN** `scripts/proof.sh --all` runs
- **THEN** it reports `PASS: deploy-targets fixtures`, and the fixture output lists an `ok:` line for each created-guest scenario
- **proof:** unit (`scripts/proof.sh --all`)

### Requirement: What a merge deploys is documented

`docs/deploy-runner.md` SHALL state that a merge deploys the `03_SERVICES`
playbooks its `ansible/` diff affects plus those of every guest the same run's
`apply` created, that a created guest without a service playbook gets nothing,
and that a recreated guest still needs the manual `deploy_runner.yml` re-pin.

#### Scenario: Reader checks what a new guest gets
- **WHEN** Rue reads `docs/deploy-runner.md` before adding a guest in `hosts.auto.tfvars`
- **THEN** it says the guest's service playbooks run in the same workflow run, that a bare guest gets none, and that a recreated guest still needs `deploy_runner.yml`
- **proof:** manual (doc review at Gate 2)

