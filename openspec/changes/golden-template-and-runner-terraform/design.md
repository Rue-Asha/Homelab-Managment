## Context

Today a new guest needs four hand-driven steps before it is managed: `terraform apply` (root key seeded), `bootstrap.yml` as root (creates `ansible`, then `common` closes root login), `deploy_runner.yml` (pins the host key, allowlists the guest in the runner's egress firewall) and a bootstrap re-run as `ansible` (authorises the deploy key). `~/.ssh/Proxmox` is node key, guest-root key and `ansible` key at once. Terraform runs only from the workstation with local, git-ignored state; `runner01` can reach guests but `proxmox1` is dropped at its firewall by design.

Constraints from the repo: no Terraform provisioners, Ansible never creates guests, the runner never manages itself, deploy logs are public (no `--diff`, no `-v`), and secrets reach jobs through the runner's `.env`, not GitHub secrets.

## Goals / Non-Goals

**Goals:** a guest is Ansible-manageable the moment it boots; every credential has one purpose; infrastructure changes flow through merge → plan → approval → apply on `runner01`.

**Non-Goals:** see proposal. Also not designing Vault, PVE-as-code, or a VM template.

## Decisions

### D1. The template carries public keys only, read from the repo
Public keys live in `ansible/keys/{guest,deploy}_ed25519.pub`, committed. The template build script and `guest_bootstrap` both read them there, replacing the `~/.ssh/Proxmox.pub` and `~/.config/homelab/deploy_ed25519.pub` lookups. Private halves never enter the repo or the template.
*Alternative:* keep reading from `~/.config`. Rejected: the build is then unreproducible from a clone, and the runner's key had to be fetched by hand.

### D2. Build with a node-side script, not Terraform/Packer
`scripts/build-lxc-template.sh <version>` runs on `proxmox1` (over the node key from the workstation): `pct create` from the stock Debian 13 template, `pct exec`/`pct push` the customisation, stop, repack the rootfs to `local:vztmpl/homelab-debian-13-<version>.tar.zst`, destroy the scratch container. Neither the provider nor Packer can produce an LXC rootfs template. The script is idempotent per version (refuses to overwrite). Run from the workstation, not the runner (the runner has no node SSH).
Contents: `sudo`, `python3`, `ansible` user + both public keys, `NOPASSWD` sudoers (visudo-validated), `PermitRootLogin no` / `PasswordAuthentication no` drop-in, `/etc/ssh/ssh_host_*` and `machine-id` removed, plus a first-boot oneshot (`ssh-keygen -A`, guarded by `ConditionPathExists=!`) so each guest generates unique host keys. Verified in task 2.4 rather than assumed, since PVE may already regenerate them.
The template does not run `common`; Ansible still owns hardening and drift.

### D3. Rotation stays in Ansible
`guest_bootstrap` shrinks to the `exclusive` authorized_keys task (guest + deploy key from D1) and `bootstrap.yml` becomes one play as `ansible` + `common`. A baked key in an old template is only a first-contact seed; `exclusive` overwrites it everywhere. This is also what strips the deploy key from `runner01` (`guest_bootstrap_authorize_deploy_key: false` in `group_vars/github_runner`) after the template put it there. `proxmox1` is not a `proxmox_guest` and is never touched.

### D4. Template bumps never replace containers
`proxmox_lxc` lifecycle becomes `ignore_changes = [description, operating_system]`. Consequence: changing the template reference never touches existing hosts; re-imaging a host is an explicit `terraform apply -replace=…`. Terraform stops passing `initialization.user_account.keys` (root gets no key).

### D5. Four credentials
| Credential | Private key / secret lives | Authorised / valid on |
|---|---|---|
| node key `homelab_node_ed25519` | workstation | `root@proxmox1` (provider SSH fallback, `proxmox_lxc_tun`) |
| guest key `homelab_guest_ed25519` | workstation | `ansible@proxmox_guest` |
| deploy key `deploy_ed25519` | `runner01` (generated there, as today) | `ansible@proxmox_guest` except `runner01` |
| runner Terraform credentials | `~github-runner/.config/homelab/terraform.env` | its own `terraform-deploy-node@pve!<id>` API token; **no node SSH** unless task 3.2 proves it unavoidable |

`~/.ssh/Proxmox` is removed from the node's and every guest's `authorized_keys` last. Variables and `ansible.cfg` are renamed to match; `proxmox_node` gets its key through the rendered inventory (`ansible_ssh_private_key_file`), the global `private_key_file` is the guest key. The provider `ssh {}` block becomes a `dynamic` block that is absent when no SSH user is configured, so the runner applies with the API token alone.
*Alternative:* a scoped non-root SSH user with limited sudo on the node, if 3.2 finds SSH-only operations.

### D6. Terraform runs inside `deploy.yml`, not a second workflow
`workflow_run` is an untrusted-trigger class that `workflow-triggers.py` forbids next to a self-hosted runner, and two workflows on one push cannot be ordered. So `deploy.yml` gets jobs `plan` → `apply` → `deploy`:
- `plan` (runs only if the push touches `terraform/**` or `ansible/inventory/00-terraform*`): `terraform plan -out=<sha>.tfplan`, saved on the runner; the log shows only resource address + action per line (logs are public), then `scripts/checks/plan-protected.sh` fails the run if `runner01` has a `delete`/`replace` action.
- `apply`: `environment: infrastructure` (new; branch policy `main`, required reviewer), applies exactly that saved plan (Terraform rejects a stale one), then scans host keys of newly created guests into `known_hosts`.
- `deploy`: `needs: apply`, runs when `apply` succeeded or was skipped.
One workflow, one concurrency group, same triggers (`push` to `main`, `workflow_dispatch`). No plan on pull requests; the approval summary is the plan view. To read full values, run `terraform plan` on `runner01` as `github-runner`.
*Alternative:* `terraform.yml` on `paths`. Rejected for the ordering reason above.

### D7. State lives on runner01 only
The backend is `backend "local" {}` with the path supplied at init (`-backend-config=path=~github-runner/.local/state/homelab/terraform.tfstate`), outside the job workspace that every job wipes. Terraform's file lock plus the single workflow concurrency group serialise applies. The workstation stops running Terraform, so there is never a second copy to diverge. A lost state is recoverable by `imports.tf` (one apply), as `docs/terraform-ansible-split.md` already says.
Consequence: `runner01` is now the state host. It is on the protected list (D6) and a rebuilt runner needs the state restored from a backup (task 6.6) before the next plan.
*Alternative:* S3/MinIO backend with locking, so both machines can apply. Rejected by the user: everything runs on the runner. It would have bought workstation plans and a state copy off the runner.

### D8. The inventory stops being committed
With apply on the runner, a committed `00-terraform.yml` would need the runner to push to `main`, re-triggering the deploy. Instead the runner renders it from `terraform output` (reads state only, no Proxmox access) in the `deploy` job and also leaves a copy at `~github-runner/.cache/homelab/00-terraform.yml`. The workstation gets it with `scripts/fetch-inventory.sh`, which reads that copy over SSH as `ansible` (passwordless sudo, existing guest key; no new permission). The file is git-ignored. The reviewed diff is the `hosts.auto.tfvars` change plus the plan summary.
*Cost:* inventory no longer appears in diffs. CI needs no fixture: proof passes without the file.

### D9. New-guest reach without touching the runner's config
- Host keys: the `apply` job runs `ssh-keyscan` for guests the plan *created* and appends to `known_hosts` — the same trust moment `deploy_runner.yml` uses today. Keys of existing guests are never overwritten; a changed key still fails the deploy.
- Egress: instead of one allowlist entry per guest, `deploy_runner.yml` allows TCP 22 to the declared guest range (`guest_cidr` in group vars) **minus** the node and the runner. New guests inside the range need no runner reconfiguration.

### D10. The widened boundary (the decision this change makes)
`runner01` may reach `proxmox1` on TCP 8006 only (SSH to the node stays dropped); TCP 443 already covers the provider registry. Accepted risk: a merged change to `main` that passes `infrastructure` approval can alter the hypervisor. Mitigations: a distinct `terraform-deploy-node@pve` user and role (no `Sys.*`, no user/ACL admin) so the workstation token and the runner token revoke independently; approval gate; applying a saved plan; protected-host check; public logs carry no plan detail.

## Risks / Trade-offs

- [Runner compromise reaches the hypervisor API] → D10 mitigations; revisit with a separate runner if the exposure grows.
- [Self-approval: sole reviewer is the author] → the gate is a pause to read the plan summary, not separation of duties; accepted for a solo repo.
- [The only copy of state is on runner01] → protected from destroy (D6); vzdump backup of `runner01` and a periodic copy of the state file to the workstation via the fetch script (6.6); `imports.tf` remains the recovery path.
- [Saved plan lives on the runner] → keyed by commit SHA, deleted after apply, never uploaded as an artifact (plans embed values).
- [Lockout while re-keying existing guests] → migration order below authorises the new key before the old one is removed.
- [Provider SSH fallback still needed] → 3.2 spike; fall back to a scoped non-root node user rather than giving the runner root.
- [Template ages] → versioned names; `common` applies upgrades; rebuild is a conscious script run, never automatic.

## Migration Plan

1. Generate node/guest keys; commit the two public keys; install the node key on `proxmox1`.
2. Copy the workstation's state file to the runner's state path (once), confirm a runner `plan` shows no changes, then stop running Terraform locally.
3. Run `guest_bootstrap` as `ansible` on all guests authorising **old and new** guest key; switch `ansible.cfg` to the new key; run again with new key only.
4. Build the template; change `lxc_template_file_id`; drop root key seeding (plan must show no replacements — D4).
5. Create the runner's `terraform-deploy-node@pve` token and role; install `terraform` + env file; update firewall (8006, guest range); add `infrastructure` environment.
6. Land the workflow change; first run is a `workflow_dispatch` no-op plan.
7. Remove `~/.ssh/Proxmox` from the node and every guest; delete the key.
Rollback: until step 7, the old key still works everywhere; the workflow can be disabled in the Actions UI and Terraform run from the workstation again with the original state file (keep it until step 7).

## Open Questions

- Which provider operations (container `features`, template upload) really need node SSH? Spike 3.2, partial (2026-10-05): with an API token and `pve_ssh_enabled=false`, refresh of all three LXC guests and `plan` succeed once the role is granted to the token itself (privilege separation: a role on the user alone gives 403 `VM.Audit`). The plan was a no-op, so create, update and destroy are untested; `features` are only `nesting` (settable without root). The template is built on the node by `scripts/build-lxc-template.sh`, not uploaded by the provider, so no upload path needs SSH. Remaining check: create and destroy of a throwaway guest in 6.3.
- ~~`guest_cidr` and the shared /24~~ Settled in 4.3: the node and runner share `192.168.0.0/24`; `group_vars/github_runner` allows SSH to the whole range and drops the node first.
- ~~Does `proof.sh` need an inventory?~~ Settled in 5.5: no. Syntax-check and lint pass with `00-terraform.yml` absent, so no fixture inventory is added.
- ~~State backend~~ Settled: runner-local state (D7), no MinIO/S3.

## Contracts

- Key files: `ansible/keys/guest_ed25519.pub`, `ansible/keys/deploy_ed25519.pub`.
- Template reference: `local:vztmpl/homelab-debian-13-<version>.tar.zst`, consumed via `lxc_template_file_id`.
- `scripts/render-inventory.sh` (on the runner) → writes `ansible/inventory/00-terraform.yml` (git-ignored); `scripts/fetch-inventory.sh` (workstation) → pulls the runner's copy.
- `scripts/checks/plan-protected.sh <plan.json>` → exit non-zero if a protected host (default `runner01`) is deleted or replaced.
- Runner env file `~github-runner/.config/homelab/terraform.env`: `PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN`, `TF_VAR_pve_ssh_enabled=false`.
