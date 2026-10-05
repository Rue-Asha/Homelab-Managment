# Check runner

`check01` is the shared check host: self-hosted GitHub Actions runners that run
the PR checks of every repo that deploys to the homelab (`Homelab-Managment`,
`Life-Manager`, `Rues-Arcade`; the list is `check_runner_repos` in
`group_vars/check_runner`). For this repo that is `proof`
(`scripts/proof.sh --all`, from `.github/workflows/ci.yml`). It is the PR-facing
counterpart to `runner01`, the deploy runner (`docs/deploy-runner.md`), and is
built the other way round: `runner01` holds the credentials and never sees PR
code, `check01` sees PR code and holds nothing.

**Why one runner per repo.** `Rue-Asha` is a personal account, so GitHub has no
account-wide runners or runner groups: a runner belongs to exactly one
repository. An organisation would give real groups, but moving the repos changes
every URL and breaks the `Rue-Asha.github.io` user Pages site. So the role runs
one instance per listed repo on the one host, and registration is automated.
Release builds never run here: a tarball that gets deployed is built on
`ubuntu-24.04`.

## What it holds and reaches

| | `check01` |
|---|---|
| Credentials | None. No deploy key, vault password, PVE token or GitHub secret |
| Outbound network | DNS and TCP 80/443 to non-private addresses. No guest, no `proxmox1`, no `runner01` |
| Users | One per repo, `check-runner-<slug>`, home `0700`, no sudo, unit `check-runner-<slug>` with `NoNewPrivileges` |
| Tools | Terraform and tflint in `/usr/local/bin`, ansible-core, ansible-lint and checkov in `/opt/check-runner/venv`. All root-owned |
| Workspace | Emptied by a per-instance root-owned hook before every job |
| Label | `homelab-check` on every instance (never `homelab-deploy`) |

The runner is persistent, not ephemeral: an ephemeral one needs a registration
credential on the box. The cost is that a malicious job could leave state for
the next one; since the box holds and reaches nothing, the worst outcome is a
wrong green `proof`. Every repo requires approval for outside contributors' workflow runs (the
playbook refuses to register otherwise), and every PR is reviewed before
merging.

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

3. **Configure and register the runners.** Prerequisites on the workstation:
   `gh auth status` logged in with admin on every listed repo, and each repo's
   fork-PR approval set to "all external contributors" (Settings → Actions →
   General). The playbook reads that setting and fails, naming the repo, if it
   differs; it never changes it. It mints each registration token with `gh`
   itself, only for instances that aren't registered yet:

       ansible-playbook ansible/playbooks/01_BASE_CONFIGURATION/check_runner.yml

   Each repo's Settings → Actions → Runners shows one runner
   `check01-<slug>`, `idle`, with the label `homelab-check`. A second run mints
   nothing and changes nothing.

4. **Check the boundaries** on `check01`, as one instance's user
   (`sudo -u check-runner-<slug> -i` from the `ansible` user):

   - `ssh ansible@192.168.0.223 true` fails
   - `curl -k --max-time 5 https://192.168.0.22:8006` fails
   - `curl -I https://github.com` succeeds
   - `sudo -n true` fails
   - `touch /usr/local/bin/terraform` fails
   - `find ~ /etc -name '*.env' -o -name 'id_*'` lists nothing but the runner's own `.env`
   - `ls /home/check-runner-<other-slug>` fails with permission denied (a job in
     one repo cannot read another repo's runner)

5. **Flip `ci.yml`.** In a separate PR set the `proof` job to
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
- **Re-register one instance:** delete `~check-runner-<slug>/actions-runner/.runner`
  and re-run; a fresh token is minted for it.
- **Add a repo:**
  1. Set its fork-PR approval to "all external contributors".
  2. Append `- repo: Rue-Asha/<name>` to `check_runner_repos`.
  3. Run `check_runner.yml`. Only the new instance registers; the others are
     not restarted.
  4. Set `runs-on: [self-hosted, homelab-check]` on its PR check jobs. Keep
     release builds on `ubuntu-24.04`.
- **Remove a repo:**
  1. Delete its entry from `check_runner_repos` and re-run `check_runner.yml`.
     This stops and disables `check-runner-<slug>`; it removes nothing else.
  2. Delete the registration:
     `gh api repos/Rue-Asha/<name>/actions/runners --jq '.runners[] | select(.name=="check01-<slug>") | .id'`,
     then `gh api -X DELETE repos/Rue-Asha/<name>/actions/runners/<id>`.
  3. On `check01`: `rm /etc/systemd/system/check-runner-<slug>.service`,
     `rm /usr/local/lib/check-runner/<slug>-job-started.sh`, then
     `userdel -r check-runner-<slug>`.
- **Changes to the role never deploy on merge:** the playbook is outside
  `02_SERVICES`.

## When `check01` is down

A queued check blocks every merge in every listed repo. In each, change the
`runs-on` of the PR check back to a hosted runner. The check name stays the same,
so branch protection needs no change. Revert when `check01` is back.

- **`Homelab-Managment`:** `runs-on` of `proof` in `ci.yml` back to
  `ubuntu-24.04`, and restore the tool setup steps from before the flip
  (`git log -p -- .github/workflows/ci.yml`).
- **`Life-Manager`, `Rues-Arcade`:** in `ci.yml`, change the caller's `runner`
  input from `["self-hosted","homelab-check"]` to `["ubuntu-24.04"]`.
