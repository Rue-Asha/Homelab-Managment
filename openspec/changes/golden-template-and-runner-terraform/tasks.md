## 1. Key split and shared contracts

> unit: depends=none · files=ansible/keys/*, ansible/ansible.cfg, ansible/roles/guest_bootstrap/defaults/main.yml, terraform/environments/homelab/variables.tf, terraform/environments/homelab/ansible.tf, scripts/proof.sh

- [x] 1.1 Generate node and guest ed25519 pairs outside the repo (`~/.ssh/homelab_node_ed25519`, `~/.ssh/homelab_guest_ed25519`); copy the deploy public key from `~/.config/homelab/deploy_ed25519.pub`; commit the guest and deploy public keys as `ansible/keys/guest_ed25519.pub` and `ansible/keys/deploy_ed25519.pub`
- [x] 1.2 Rename Terraform variables (`pve_ssh_private_key_path` → node key, drop `ssh_public_key_path`), point `ansible.cfg` `private_key_file` at the guest key, and give `proxmox_node` the node key via the rendered inventory (`ansible_ssh_private_key_file`)
- [x] 1.3 Make `guest_bootstrap_ssh_public_key` and the deploy-key lookup read `ansible/keys/*.pub`
- [x] 1.4 Add a `proof.sh` check that fails on any `ssh/Proxmox` reference, written from "Scenario: The old path is searched for"
- [x] 1.5 Stub `scripts/render-inventory.sh` and `scripts/checks/plan-protected.sh` (usage + exit codes only) so later groups share the contract

## 2. Golden LXC template

> unit: depends=1 · files=scripts/build-lxc-template.sh, terraform/modules/proxmox_lxc/main.tf, terraform/modules/proxmox_lxc/variables.tf, terraform/environments/homelab/containers.tf, ansible/roles/guest_bootstrap/**, ansible/playbooks/02_BASE_CONFIGURATION/bootstrap.yml, ansible/inventory/group_vars/github_runner/*

- [x] 2.1 Write `scripts/build-lxc-template.sh <version>`: scratch `pct create` from stock Debian 13, install `sudo`/`python3`, create `ansible` + authorized keys from `ansible/keys/`, `visudo`-validated sudoers, `PermitRootLogin no`/`PasswordAuthentication no` drop-in, remove host keys and `machine-id`, add the guarded first-boot `ssh-keygen -A` unit, repack to `homelab-debian-13-<version>.tar.zst`, destroy the scratch container; refuse an existing version
- [x] 2.2 Add `operating_system` to `ignore_changes` in `proxmox_lxc`, with the "re-image via -replace" consequence in the comment; remove `ssh_public_keys` from the module and `containers.tf`
- [x] 2.3 Reduce `guest_bootstrap` to the `exclusive` authorized_keys task (guest + deploy key, deploy key off on `runner01`); delete `python.yml`, `packages.yml`, `account.yml`, `sudo.yml` from the role; rewrite `bootstrap.yml` as one play as `ansible` with `become` plus `common`
- [x] 2.4 Run the build for a first version on `proxmox1` (⚠ irreversible: creates the template file; scratch container destroyed on exit); create a throwaway container from it and confirm unique host keys, `ansible` login with both keys, no root login, per "Scenario: A guest is created from the template" and "Scenario: Two guests from one template"
- [x] 2.5 `terraform plan` after pointing `lxc_template_file_id` at the new template; confirm zero replacements per "Scenario: The template reference is bumped"

## 3. Runner-held state and Terraform credentials

> unit: depends=1 · files=terraform/environments/homelab/{backend.tf,providers.tf,variables.tf,versions.tf}, terraform/README.md

- [x] 3.1 Replace the backend decision: `backend "local" {}` with the path passed by `scripts/tf-ci.sh` (`-backend-config`), state under `~github-runner/.local/state/homelab/`; no `state01`, no MinIO/S3
- [x] 3.2 Spike: apply the existing configuration with an API token only (no `ssh {}` block) and list which provider operations fail; record the result in `design.md` Open Questions (read/refresh/plan proven; create/destroy ride on 6.3)
- [x] 3.3 Make the provider `ssh` block `dynamic`, absent when no SSH user is configured; if 3.2 found SSH-only operations, add the scoped non-root node user and sudoers rule instead of giving the runner root
- [x] 3.4 Create the `terraform-deploy-node@pve` user, custom role and token (⚠ irreversible on the live PVE) with only guest lifecycle privileges; record the privilege list in `terraform/README.md`
- [x] 3.4b Write `~/.config/homelab/runner_terraform.env` on the workstation from the 3.4 token (mode 0600, content as in `terraform/README.md` "Runner credentials", never echoed); `deploy_runner.yml` pushes it to the runner and now fails if it is missing
- [x] 3.5 Copy the workstation's state file to the runner's state path (⚠ irreversible on the live runner: becomes the only copy; keep the original until 6.7); confirm a runner `plan` shows no changes per "Scenario: A job wipes its workspace"

## 4. Widen runner01

> unit: depends=3 · files=ansible/roles/github_runner/**, ansible/roles/egress_firewall/**, ansible/playbooks/02_BASE_CONFIGURATION/deploy_runner.yml, ansible/inventory/group_vars/github_runner/*, ci/requirements.txt, docs/deploy-runner.md

- [x] 4.1 Install a pinned `terraform` (and the provider mirror/registry reach via 443) on the runner through the `github_runner` role; pin the version in `ci/`
- [x] 4.2 Place `~github-runner/.config/homelab/terraform.env` (mode 0600, written from the vaulted token, not echoed) and hand it to jobs through the runner's `.env` like `vault_pass`
- [x] 4.3 Change the egress rules: TCP 22 to `guest_cidr` minus node and runner, TCP 8006 to `proxmox_node` hosts, node SSH still dropped; settle whether the node and runner share the guest `/24` and order drops before the allow accordingly
- [x] 4.4 Run `deploy_runner.yml` (⚠ irreversible on the live runner: rewrites its firewall and env); verify from `runner01` as `github-runner`: `curl -k https://192.168.0.22:8006` works, `ssh root@192.168.0.22` fails, `curl -I https://github.com` works
- [x] 4.5 Rewrite the boundary section of `docs/deploy-runner.md` ("`proxmox1` is dropped" → API-only) and state the accepted risk and mitigations from design D10

## 5. Workflow, scripts and CI

> unit: depends=3,4 · files=.github/workflows/deploy.yml, scripts/render-inventory.sh, scripts/checks/plan-protected.sh, scripts/fetch-inventory.sh, scripts/tests/plan-protected.sh, terraform/environments/homelab/ansible.tf, terraform/environments/homelab/outputs.tf, .gitignore, ansible/inventory/00-terraform.yml, scripts/proof.sh, ansible/tests/inventory.fixture.yml

- [x] 5.1 Write `scripts/tests/plan-protected.sh` fixtures "Scenario: A protected host would be replaced" and "Scenario: An unprotected host is replaced" (unset `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE` if git is used), then implement `scripts/checks/plan-protected.sh` over `terraform show -json`; wire the test into `proof.sh`
- [x] 5.2 Expose the inventory as a Terraform output; implement `scripts/render-inventory.sh` (reads state on the runner) and `scripts/fetch-inventory.sh` (workstation pulls the runner's copy); remove `00-terraform.yml` from git (`git rm`), add it to `.gitignore`, drop the `local_file` resource
- [x] 5.3 Add `plan` and `apply` jobs to `deploy.yml` per design D6: path-gated plan saved as `<sha>.tfplan` on the runner, address+action-only log summary, protected-host check, `infrastructure` environment on `apply`, saved-plan apply, `ssh-keyscan` of created guests into `known_hosts` (never overwrite), plan file removed afterwards; `deploy` gets `needs: apply` with `if: always() && (needs.apply.result == 'success' || needs.apply.result == 'skipped')` and renders the inventory first
- [x] 5.4 Confirm `workflow-triggers.py` still passes (no new untrusted trigger) and `actionlint` is clean
- [x] 5.5 Add a fixture inventory for `proof.sh`/CI so `ansible-playbook --syntax-check` and `ansible-lint` pass without remote state; settle whether `proof.sh` needs it
- [x] 5.6 Create the `infrastructure` GitHub environment (⚠ irreversible: repo settings): branch policy `main`, required reviewer

## 6. Cutover and cleanup

> unit: depends=2,3,4,5 · files=docs/terraform-ansible-split.md, docs/party-games-webservice-architecture.md, .claude/CLAUDE.md, terraform/README.md, ansible/roles/guest_bootstrap/README.md

- [x] 6.1 Re-key existing guests: run `guest_bootstrap` as `ansible` authorising old and new guest key together, switch `ansible.cfg` to the new key, run again with the new key only (⚠ irreversible: `exclusive` replaces `authorized_keys`)
- [x] 6.2 Install the node key on `proxmox1`; remove `~/.ssh/Proxmox` from the node and every guest, then delete the key file (⚠ irreversible); verify "Scenario: Guest key against the node", "Scenario: Node key against a guest" and "Scenario: The retired key is used"
- [ ] 6.3 `workflow_dispatch` the deploy workflow for a no-op plan, approve, then merge a trivial `hosts.auto.tfvars` change for a throwaway guest and watch plan → approval → apply → deploy end to end; remove the throwaway (⚠ irreversible: live apply)
- [x] 6.4 Update `docs/terraform-ansible-split.md` (run order, secrets, state on the runner, roadmap item 3 done, item 4 not), `terraform/README.md`, the role README and the boundary lines in `.claude/CLAUDE.md` (Terraform "SSH key seeded at creation" → template; runner reach)
- [x] 6.5 Run `scripts/proof.sh --all`; green is the exit condition
- [x] 6.6 Back up the state: confirm `runner01` is in the vzdump schedule and add a periodic `scripts/fetch-state.sh`-style copy to the workstation (or accept vzdump only and say so in the docs) (no vzdump job exists on the node; `scripts/fetch-state.sh` is the manual copy, scheduling it left to the user)
- [ ] 6.7 After a week of green runs, delete the workstation's old state file (⚠ irreversible)
