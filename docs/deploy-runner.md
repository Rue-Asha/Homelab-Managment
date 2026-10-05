# Deploy runner

Merging to `main` deploys. `.github/workflows/deploy.yml` runs on `runner01`,
a self-hosted GitHub Actions runner in its own LXC. When `terraform/` changed it
first plans and, after approval in the `infrastructure` environment, applies
(`scripts/tf-ci.sh`); then it maps the merged commits' `ansible/` diff, plus
every guest that apply created, to the `02_SERVICES` playbooks they affect
(`scripts/deploy-targets.sh`) and runs each one in full with
`--limit proxmox_guest`. So a merge that only adds a guest to
`hosts.auto.tfvars` also runs that guest's service playbooks in the same run.
This page covers the runner itself: setting it up, rotating its credentials,
and deploying without it.

## What the runner holds

| On `runner01` | Purpose |
|---|---|
| `~github-runner/.ssh/deploy_ed25519` | Deploy key. Authorised for `ansible` on every guest except `runner01`, never on `proxmox1`. The public half is committed as `ansible/keys/deploy_ed25519.pub` |
| `~github-runner/.config/homelab/terraform.env` | The runner's own PVE API token (`terraform-deploy-node@pve`), state backend keys and `TF_VAR_pve_ssh_enabled=false`. Not the workstation's token |
| `~github-runner/.ssh/known_hosts` | Guest host keys, pinned when `deploy_runner.yml` last ran |
| `~github-runner/.config/homelab/vault_pass` | Ansible vault password (mode 0600) |
| `~github-runner/actions-runner/.env` | Hands the credential paths above to every job, overriding `ansible.cfg` |
| `/usr/local/bin/terraform` | Pinned in `github_runner_terraform_version`, kept in step with `ci.yml` |
| `~github-runner/ansible-venv/` | The ansible-core pinned in `ci/requirements.txt` |

**Where each secret comes from.** There is no secret manager: the workstation
pushes them when `deploy_runner.yml` runs by hand, and the play fails if a source
file is missing.

| Secret | Source on the workstation | Lands on `runner01` |
|---|---|---|
| Ansible vault password | `~/.config/homelab/vault_pass` | `~github-runner/.config/homelab/vault_pass` |
| Runner PVE token | `~/.config/homelab/runner_terraform.env` | `~github-runner/.config/homelab/terraform.env` |
| Deploy key | generated on the runner | stays there; public half fetched to `ansible/keys/` |

The vault files themselves are encrypted in the repo and arrive by checkout.
Rotating a secret means updating the workstation file and rerunning the play.

GitHub holds no secret for this repo. `github-runner` has no sudo, the unit
runs with `NoNewPrivileges`, and the `egress_firewall` role drops all outbound
traffic except DNS, SSH to the guest range, and TCP 80/443 to non-LAN addresses.
`proxmox1` is reachable on TCP 8006 (the PVE API) only; SSH to it is dropped.

**Accepted risk.** Terraform runs here, so anyone who can merge to `main` and
pass the `infrastructure` approval can change the hypervisor through the API.
That reverses the earlier "`proxmox1` is dropped outright" boundary, on purpose,
to avoid a second runner. Limits: the runner's token belongs to its own PVE user
and role (revocable independently of the workstation's), applies run only from
a saved plan that was shown as `address action` lines, `scripts/checks/plan-protected.sh`
refuses any plan that destroys `runner01` or `state01`, and the runner holds no
SSH key for the node.

## First-time setup

Order matters: the runner needs the guests' host keys, and the guests need the
runner's key.

1. **Declare and create the LXC.** `runner01` is in
   `terraform/environments/homelab/hosts.auto.tfvars` on the Debian 13
   template (the pinned ansible-core needs Python 3.12+). If the node does not
   have the template yet:

       pveam download local debian-13-standard_13.6-1_amd64.tar.zst   # on proxmox1
       terraform -chdir=terraform/environments/homelab apply

   The inventory is rendered from state and not committed; pull it with
   `scripts/fetch-inventory.sh`.

2. **Converge it** like any guest from the template (this also removes the
   deploy key the template put on it, see `group_vars/github_runner`):

       ansible-playbook ansible/playbooks/01_BASE_CONFIGURATION/bootstrap.yml -l runner01

3. **Configure and register the runner.** Get a registration token from
   GitHub → Settings → Actions → Runners → New self-hosted runner. It expires
   after an hour and is not stored anywhere:

       ansible-playbook ansible/playbooks/01_BASE_CONFIGURATION/deploy_runner.yml \
         -e github_runner_registration_token=<token>

   The runner shows as `idle` with the label `homelab-deploy`. The play also
   fetches the deploy key's public half to `ansible/keys/deploy_ed25519.pub`.
   Commit it: the template build and `guest_bootstrap` read it from there.

4. **Authorise the deploy key on the guests.** Guests built from the template
   already carry it. For older ones, converge them:

       ansible-playbook ansible/playbooks/01_BASE_CONFIGURATION/bootstrap.yml

5. **Check the boundaries** from `runner01` as `github-runner`:
   `ssh ansible@192.168.0.223 true` works, `ssh ansible@192.168.0.22 true` is
   refused, `curl -k https://192.168.0.22:8006` answers, `ssh root@192.168.0.22 true`
   fails, and `curl -I https://github.com` succeeds.

## Day 2

- **A guest was recreated** (new host key): its next deploy fails with a
  host-key verification error. That is deliberate. Re-run `deploy_runner.yml`
  (no token needed) to re-scan, then re-run the failed deploy.
- **A guest was added by the pipeline:** nothing to do. The `apply` job pins its
  host key and hands the guest to `deploy`, which runs every `02_SERVICES`
  playbook targeting it in the same workflow run; the firewall allows the whole
  guest range. A bare guest that no `02_SERVICES` playbook targets gets none,
  and the log says so. This covers created guests only: a recreated one still
  needs `deploy_runner.yml`, see above.
- **A guest was added by hand** (outside the pipeline): run `deploy_runner.yml`
  so its host key is pinned.
- **Rotate the deploy key:** delete `~github-runner/.ssh/deploy_ed25519*` on
  `runner01`, re-run `deploy_runner.yml`, commit the new
  `ansible/keys/deploy_ed25519.pub`, then run step 4. `exclusive` on the
  authorised keys drops the old key. Rebuild the template to bake the new one in.
- **Re-register** (runner removed in GitHub, or `runner01` recreated): delete
  `~github-runner/actions-runner/.runner` and re-run `deploy_runner.yml` with
  a fresh token.
- **Upgrade the runner:** bump `github_runner_version` and
  `github_runner_sha256` together (the SHA is in the release notes), then
  re-run `deploy_runner.yml`. Self-update is disabled.

Changes to the runner's roles never deploy on merge: the runner playbook is
outside `02_SERVICES` because a deploy that restarted its own runner would kill
the job running it. They take effect at the next manual `deploy_runner.yml`.

## Deploying without the runner

Everything the workflow does is a plain playbook run, so the workstation can
always deploy directly, with the same smoke check and rollback:

    scripts/deploy-targets.sh <before-sha> <after-sha>   # or --all, or a name
    ansible-playbook ansible/playbooks/02_SERVICES/life-manager.yml

To redeploy from GitHub without a code change, run the `deploy` workflow by
hand (Actions → deploy → Run workflow) with a playbook name or `all`. It only
runs from `main`: the `production` environment rejects other branches.

To stop deploys entirely, disable the `deploy` workflow in the Actions UI.
Manual runs keep working because `ansible.cfg` is untouched.
