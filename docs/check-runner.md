# Check runner

`check01` is the self-hosted GitHub Actions runner the CI `proof` check runs on
(`scripts/proof.sh --all`, from `.github/workflows/ci.yml`). It is the PR-facing
counterpart to `runner01`, the deploy runner (`docs/deploy-runner.md`), and is
built the other way round: `runner01` holds the credentials and never sees PR
code, `check01` sees PR code and holds nothing.

## What it holds and reaches

| | `check01` |
|---|---|
| Credentials | None. No deploy key, vault password, PVE token or GitHub secret |
| Outbound network | DNS and TCP 80/443 to non-private addresses. No guest, no `proxmox1`, no `runner01` |
| User | `check-runner`, no sudo, `NoNewPrivileges` |
| Tools | Terraform and tflint in `/usr/local/bin`, ansible-core, ansible-lint and checkov in `/opt/check-runner/venv`. All root-owned |
| Workspace | Emptied by a root-owned hook before every job |
| Label | `homelab-check` (never `homelab-deploy`) |

The runner is persistent, not ephemeral: an ephemeral one needs a registration
credential on the box. The cost is that a malicious job could leave state for
the next one; since the box holds and reaches nothing, the worst outcome is a
wrong green `proof`. Only Rue can open PRs on this repo, and every PR is
reviewed before merging.

`scripts/checks/workflow-triggers.py` allows exactly `[self-hosted, homelab-check]`
under a PR trigger and refuses everything else, including `homelab-deploy`. It
runs from the PR's own checkout, so it guards against mistakes, not against a
PR that edits the check itself.

## First-time setup

1. **Create the LXC.** `check01` is in `terraform/environments/homelab/hosts.auto.tfvars`.
   Merging that change runs the `deploy` workflow: approve the `infrastructure`
   environment and `apply` creates it. Pull the inventory with
   `scripts/fetch-inventory.sh`.

2. **Converge it** like any guest from the template (this removes the deploy key
   the template put on it, see `group_vars/check_runner`):

       ansible-playbook ansible/playbooks/01_BASE_CONFIGURATION/bootstrap.yml -l check01

3. **Configure and register the runner.** Get a registration token from GitHub →
   Settings → Actions → Runners → New self-hosted runner (valid one hour, not
   stored):

       ansible-playbook ansible/playbooks/01_BASE_CONFIGURATION/check_runner.yml \
         -e check_runner_registration_token=<token>

   The runner shows as `idle` with the label `homelab-check`.

4. **Check the boundaries** on `check01`, as `check-runner`
   (`sudo -u check-runner -i` from the `ansible` user):

   - `ssh ansible@192.168.0.223 true` fails
   - `curl -k --max-time 5 https://192.168.0.22:8006` fails
   - `curl -I https://github.com` succeeds
   - `sudo -n true` fails
   - `touch /usr/local/bin/terraform` fails
   - `find ~ /etc -name '*.env' -o -name 'id_*'` lists nothing but the runner's own `.env`

5. **Confirm GitHub's fork-PR setting:** Settings → Actions → General → "Require
   approval for all outside collaborators". The repo is public.

6. **Flip `ci.yml`.** In a separate PR set the `proof` job to
   `runs-on: [self-hosted, homelab-check]` and drop the steps that install the
   tools (`setup-python`, `pip install`, `setup-terraform`, `setup-tflint`). Keep
   the collections, dummy vault and placeholder key steps. The `proof` check must go
   green on `check01` before that PR merges. `security-baseline` stays on its
   GitHub-hosted reusable workflow.

## Day 2

- **Bump a tool:** `ci/requirements.txt` for ansible-core, ansible-lint and
  checkov; `check_runner_terraform_version` and `_sha256` for Terraform (keep it
  equal to `github_runner_terraform_version`); `check_runner_tflint_version` and
  `_sha256` for tflint. Then re-run `check_runner.yml`. Until that run `proof`
  still uses the old version, so a PR that bumps a pin is not tested against it.
- **Upgrade the runner:** bump `check_runner_version` and `_sha256` together,
  re-run `check_runner.yml`.
- **Re-register:** delete `~check-runner/actions-runner/.runner` and re-run with a
  fresh token.
- **Changes to the role never deploy on merge:** the playbook is outside
  `02_SERVICES`.

## When `check01` is down

A queued `proof` blocks every merge. To run `proof` on GitHub's runner again,
change `runs-on` in `ci.yml` back to `ubuntu-24.04` and restore the tool setup
steps from before the flip (`git log -p -- .github/workflows/ci.yml`). The check
name stays `proof`, so branch protection needs no change. Revert when `check01`
is back.
