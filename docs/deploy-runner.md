# Deploy runner

Merging to `main` deploys. `.github/workflows/deploy.yml` runs on `runner01`,
a self-hosted GitHub Actions runner in its own LXC, maps the merged commits to
the `03_SERVICES` playbooks they affect (`scripts/deploy-targets.sh`) and runs
each one in full with `--limit proxmox_guest`. This page covers the runner
itself: setting it up, rotating its credentials, and deploying without it.

## What the runner holds

| On `runner01` | Purpose |
|---|---|
| `~github-runner/.ssh/deploy_ed25519` | Deploy key. Authorised for `ansible` on every guest except `runner01`, never on `proxmox1` |
| `~github-runner/.ssh/known_hosts` | Guest host keys, pinned when `deploy_runner.yml` last ran |
| `~github-runner/.config/homelab/vault_pass` | Ansible vault password (mode 0600) |
| `~github-runner/actions-runner/.env` | Hands the three above to every job, overriding `ansible.cfg` |
| `~github-runner/ansible-venv/` | The ansible-core pinned in `ci/requirements.txt` |

GitHub holds no secret for this repo. `github-runner` has no sudo, the unit
runs with `NoNewPrivileges`, and the `egress_firewall` role drops all outbound
traffic except DNS, SSH to the guests, and TCP 80/443 to non-LAN addresses.
`proxmox1` is dropped outright.

## First-time setup

Order matters: the runner needs the guests' host keys, and the guests need the
runner's key.

1. **Declare and create the LXC.** `runner01` is in
   `terraform/environments/homelab/hosts.auto.tfvars` on the Debian 13
   template (the pinned ansible-core needs Python 3.12+). If the node does not
   have the template yet:

       pveam download local debian-13-standard_13.6-1_amd64.tar.zst   # on proxmox1
       terraform -chdir=terraform/environments/homelab apply

   Commit the regenerated `ansible/inventory/00-terraform.yml`.

2. **Bootstrap it** like any fresh guest:

       ansible-playbook ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml -l runner01

3. **Configure and register the runner.** Get a registration token from
   GitHub → Settings → Actions → Runners → New self-hosted runner. It expires
   after an hour and is not stored anywhere:

       ansible-playbook ansible/playbooks/02_BASE_CONFIGURATION/deploy_runner.yml \
         -e github_runner_registration_token=<token>

   The runner shows as `idle` with the label `homelab-deploy`. The play also
   fetches the deploy key's public half to
   `~/.config/homelab/deploy_ed25519.pub` on the workstation.

4. **Authorise the deploy key on the guests.** Bootstrap is one-shot as root,
   so re-run it as `ansible` instead:

       ansible-playbook ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml \
         -e guest_bootstrap_connect_user=ansible --become

5. **Check the boundaries** from `runner01` as `github-runner`:
   `ssh ansible@192.168.0.223 true` works, `ssh ansible@192.168.0.22 true` is
   refused, `curl -k https://192.168.0.22:8006` fails, and
   `curl -I https://github.com` succeeds.

## Day 2

- **A guest was recreated** (new host key): its next deploy fails with a
  host-key verification error. That is deliberate. Re-run `deploy_runner.yml`
  (no token needed) to re-scan, then re-run the failed deploy.
- **A guest was added:** run step 4 for it after its bootstrap, then
  `deploy_runner.yml` so its host key is pinned and the firewall allows it.
- **Rotate the deploy key:** delete `~github-runner/.ssh/deploy_ed25519*` on
  `runner01`, re-run `deploy_runner.yml`, then step 4. `exclusive` on the
  authorised keys drops the old key.
- **Re-register** (runner removed in GitHub, or `runner01` recreated): delete
  `~github-runner/actions-runner/.runner` and re-run `deploy_runner.yml` with
  a fresh token.
- **Upgrade the runner:** bump `github_runner_version` and
  `github_runner_sha256` together (the SHA is in the release notes), then
  re-run `deploy_runner.yml`. Self-update is disabled.

Changes to the runner's roles never deploy on merge: the runner playbook is
outside `03_SERVICES` because a deploy that restarted its own runner would kill
the job running it. They take effect at the next manual `deploy_runner.yml`.

## Deploying without the runner

Everything the workflow does is a plain playbook run, so the workstation can
always deploy directly, with the same smoke check and rollback:

    scripts/deploy-targets.sh <before-sha> <after-sha>   # or --all, or a name
    ansible-playbook ansible/playbooks/03_SERVICES/life-manager.yml

To redeploy from GitHub without a code change, run the `deploy` workflow by
hand (Actions → deploy → Run workflow) with a playbook name or `all`. It only
runs from `main`: the `production` environment rejects other branches.

To stop deploys entirely, disable the `deploy` workflow in the Actions UI.
Manual runs keep working because `ansible.cfg` is untouched.
