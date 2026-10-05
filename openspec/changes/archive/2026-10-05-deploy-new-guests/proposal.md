## Why

A merge that adds a guest only to `terraform/environments/homelab/hosts.auto.tfvars`
creates the LXC and pins its host key, but configures nothing. `scripts/deploy-targets.sh`
only diffs `ansible/`, so the new guest stays empty until some later change touches its
Ansible files. Rue hit this while preparing the `pihole01` rebuild.

## What Changes

- **S1** The `apply` job reports the guests this apply created (the same set whose host keys
  `scripts/tf-ci.sh apply` pins) as a job output, and the `deploy` job hands that list to
  `scripts/deploy-targets.sh`.
- **S2** `scripts/deploy-targets.sh` takes the created guests as an extra input and treats each
  like a changed host: every `03_SERVICES` playbook whose `--list-hosts` contains it is selected,
  merged and de-duplicated with the playbooks the `ansible/` diff already selects, in the existing
  order. A created guest with no service playbook is logged; an unknown host name fails the run.
- **S3** The fixture tests in `scripts/tests/deploy-targets.sh` cover S2 and its edges; `proof.sh`
  already runs them when the script or its tests change.
- **S4** `docs/deploy-runner.md` says what a merge deploys, and the `continuous-deployment` spec
  says a newly created guest gets its service playbooks in the same run.

Unchanged: a merge that touches only `ansible/` selects playbooks exactly as today, and
`workflow_dispatch` (`all`, `life-manager`) behaves as today.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities
- `continuous-deployment`: the deploy also runs the `03_SERVICES` playbooks of guests the same run's `apply` created; the apply job hands that list to the deploy job; docs say so.

## Non-Goals

- Re-pinning the host key of a **recreated** guest (replace): stays a deliberate manual step
  (`deploy_runner.yml`), as `docs/deploy-runner.md` documents; widening trust automatically is a
  separate decision.
- Running `02_BASE_CONFIGURATION/bootstrap.yml` for new guests: the golden template already carries
  the `ansible` user, keys and SSH hardening, and `03_SERVICES` playbooks run `common`.
- A `pihole` option for `workflow_dispatch`: not needed once creates deploy themselves.
- The `pihole01` rebuild itself: split off as `rebuild-pihole01`, after this change ships.

## Done criteria

- [ ] `scripts/proof.sh --all` green, including new `deploy-targets.sh` fixtures for created guests.
- [ ] The PR's merge run deploys nothing it wouldn't have before (no guest created).
- [ ] The follow-up `pihole01` rebuild PR, which only adds tfvars + vault.yml, ends with `pihole.yml`
      run and its smoke check green in the same workflow run.

## Appetite

One session. Exceeding it means renegotiating scope.

## Impact

- `.github/workflows/deploy.yml` (apply job output, deploy job passes it on)
- `scripts/tf-ci.sh` (emit the created names from the existing create loop)
- `scripts/deploy-targets.sh`, `scripts/tests/deploy-targets.sh`
- `docs/deploy-runner.md`, `openspec/specs/continuous-deployment/spec.md` (via this change's delta)
- Risks accepted at scope: the create path with an API-token-only runner has never run live (R1);
  the `rebuild-pihole01` run is its first proof.
