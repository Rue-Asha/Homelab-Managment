## Context

The homelab is one flat `192.168.0.0/24` LAN behind a home router with no inbound ports. A Tailscale subnet router (`tailscale01`) existed until `efa9f49`, configured by a `03_SERVICES` playbook with a vaulted pre-auth key and a manual route approval. Since then guests are created only by `runner01` (merge → plan → `infrastructure` approval → apply), the inventory is rendered from runner state, the `02_SERVICES` playbooks deploy on merge, and the runner has no SSH to the node. `proxmox_lxc_tun` survived for this return; it delegates to `proxmox1` with the workstation's node key.

Problem, flows, S-items, non-goals and Done criteria are in `scope.md` and `proposal.md`; this file records how.

## Goals / Non-Goals

**Goals:** off-LAN access to the LAN by IP from Rue's three devices; a guest that is rebuilt with one merge, one prompt and no console clicks; nothing in CD that can restart the VPN.

**Non-Goals:** see `proposal.md` → Non-Goals (DNS names, exit node, Headscale, policy as code, multi-user ACLs, laptop auto-toggle, CD deploy of the role, IPv6 routes/TLS/other guests, the `workflow_dispatch` list).

## Decisions

Carried over from scope.md as decided at Gate 0:

- **Tailscale SaaS** — Rue asked for Tailscale; the free tier is enough.
- **IP-only, `--accept-dns=false`** — smallest useful step; names later.
- **Subnet router only, advertising the whole `192.168.0.0/24`** — single flat LAN, single user.
- **Operator playbook in `01_BASE_CONFIGURATION/`, never run by CD** — the runner has no node access by design; a merge must never restart the VPN.
- **`tag:subnet-router` + `autoApprovers`** — rebuilds need no clicks; tagged nodes don't expire.
- **Pre-auth key via hidden prompt, not ansible-vault** — the key is needed once and is then dead; no secret commit per rebuild. Deliberate deviation from the vault convention.
- **IP `192.168.0.230`** — the documented address, free.
- **Clients configured by hand from a checklist** — apps already installed, not Ansible-managed.

Made while planning:

- **D1 Join logic in its own task file, `tasks/join.yml`.** `main.yml` imports `install`, `configure`, `service`, `join`. `join.yml` touches only the `tailscale` CLI, so `scripts/tests/tailscale.sh` can run it alone (`include_role: tasks_from: join.yml`) against `localhost` with a stub `tailscale` on `PATH`, the pattern `scripts/tests/sqlite-backup.sh` uses for `systemctl`. That turns S4's edges into offline fixtures instead of `--check` runs, which skip `command` tasks (repo learning). Alternative: one `service.yml` as in the old role — rejected, it would drag `systemd` into the fixture.
- **D2 "Logged in" means `BackendState` is not `NeedsLogin`/`NoState` and `tailscale status --json` succeeded.** A non-zero exit of `tailscale status --json` is treated as `NoState`, so a logged-in node whose `tailscaled` is down or unreachable also counts as not logged in and needs a key; the empty-key failure message says so (`NoState` → check `tailscaled` first), so the operator is not sent to mint a key the node doesn't need. Anything else is "not logged in" and needs a key. A rerun converges `tailscale01` to `Running`: a `Stopped` node (after `tailscale down`) is still logged in, so it needs no key and no re-auth, and the role brings it back with `tailscale up --advertise-routes=… --advertise-tags=… --accept-dns=…` (the join flags without `--auth-key`). The empty-key check is an `ansible.builtin.assert` without `no_log` (repo learning: `no_log` censors `fail_msg`).
- **D3 A failed `tailscale up` is surfaced by a second task.** `tailscale up` runs with `no_log: true`, `failed_when: false`, registered; the next task fails with the registered `stderr` when `rc != 0`. With `no_log` alone the error would be censored; `stderr` never contains the key (it is only in the command line).
- **D4 Drift is read from `tailscale debug prefs` and fixed with `tailscale set`.** On a logged-in node the role compares `AdvertiseRoutes` and `CorpDNS` with the vars and runs `tailscale set --advertise-routes=… --accept-dns=…` when they differ. Tags are not converged by `set`: changing `tag:subnet-router` needs a fresh key (`tailscale up --force-reauth`), which the docs mention. The builder checks the prefs field names against upstream `ipn/prefs.go` before writing the fixture.
- **D5 Release from facts.** `tailscale_apt_release: "{{ ansible_facts['distribution_release'] | default('trixie', true) }}"`; the key and list URLs derive from it. `ansible.posix.sysctl` (already pinned) writes `/etc/sysctl.d/99-tailscale.conf`; a separate task reads `/proc/sys/...` and asserts 1.
- **D6 Two new proof sensors, no workflow change.** `tailscale fixtures` (`TAILSCALE_FIXTURES_FAILED`) runs `scripts/tests/tailscale.sh` when the role, the playbook, `host_vars/tailscale01/` or the test changes, and on `--all`. `no Tailscale auth key in the repo` (`TAILSCALE_KEY_COMMITTED`) always runs a `git grep` for key-shaped strings (`tskey-(auth|client)-` followed by a key body), so the docs' placeholder `tskey-auth-…` and the fixture's `tskey-auth-fixture` don't match. Fixture output goes to files, never through a pipe (repo learning on `ansible` and non-blocking stderr).
- **D7 The CD isolation is proven in the synthetic `deploy-targets` fixture**, like `check_runner`: a `tailscale` group, `tailscale01`, a `tailscale` role and a `01_BASE_CONFIGURATION/tailscale.yml` play are added to the fixture tree. `deploy-targets.sh` itself does not change; the fixtures are expected green on first run, as in `add-pihole`.

## Contracts

Shared by units 1–3 (they run in parallel and must agree on these names):

| Name | Value | Used by |
|---|---|---|
| Host / group / IP | `tailscale01`, group `tailscale`, `192.168.0.230/24` | U1 tfvars, U1 deploy-targets fixture, U2 playbook + host_vars, U3 docs |
| Operator playbook | `ansible/playbooks/01_BASE_CONFIGURATION/tailscale.yml`; play 1 `hosts: tailscale`, `gather_facts: false`, roles `[proxmox_lxc_tun]`; play 2 `hosts: tailscale`, `become: true`, roles `[common, tailscale]`; `vars_prompt: [{name: tailscale_authkey, prompt: …, private: true, default: ""}]` | U2, U3 docs (command line), U1 fixture (synthetic copy of the shape) |
| Host vars | `ansible/inventory/host_vars/tailscale01/vars.yml`: `proxmox_lxc_tun_enabled: true`; no `vault.yml` | U2, U3 |
| Role defaults | `tailscale_authkey: ""`, `tailscale_advertise_routes: ["192.168.0.0/24"]`, `tailscale_advertise_tags: ["tag:subnet-router"]`, `tailscale_accept_dns: false`, `tailscale_apt_release` (D5), `tailscale_apt_keyring`, `tailscale_apt_key_url`, `tailscale_apt_list_url`, `tailscale_service_name: tailscaled` | U2, U3 docs |
| Role task files | `tasks/main.yml` imports `install.yml`, `configure.yml`, `service.yml`, `join.yml` in that order | U2 |
| Join command | `tailscale up --auth-key=<key> --advertise-routes=192.168.0.0/24 --advertise-tags=tag:subnet-router --accept-dns=false`; drift: `tailscale set --advertise-routes=192.168.0.0/24 --accept-dns=false` | U2, U3 docs |
| Tag + policy | `tag:subnet-router`; snippet `"tagOwners": {"tag:subnet-router": ["autogroup:admin"]}`, `"autoApprovers": {"routes": {"192.168.0.0/24": ["tag:subnet-router"]}}` | U3 docs, U4 rollout |
| CD warning | `deploy-targets: tailscale01 has no 02_SERVICES playbook` (stderr, exit 0) | U1 fixture, U3 docs |
| Sensors | `PASS: tailscale fixtures` / `TAILSCALE_FIXTURES_FAILED`; `PASS: no Tailscale auth key in the repo` / `TAILSCALE_KEY_COMMITTED` | U2 |

## Risks / Trade-offs

- **R1 Forwarding sysctls in an unprivileged LXC** → accepted: network-namespace scoped and normally writable; the role sets and verifies them and fails loudly otherwise. Proven at the first live run.
- **R2 Live behaviour (S2, S4–S6) is provable only after merge**, because only the runner applies Terraform and the host doesn't exist before → Gate 2 evidence is lint, syntax-check and the offline fixtures; everything live is the post-merge checklist: the spec's `manual (post-merge …)` scenarios, which the verifier carries into `verification.md` for Gate 2. Rue runs them after the merge, following the post-merge runbook in `docs/tailscale-subnet-router.md` (written by unit 3); the ⚠ steps run on Rue's go. `tasks.md` holds no post-merge task, because flow enters Verify only when every box is checked.
- **R3 A LAN host accepting the /24 loses its LAN path** → resolved by S7: laptop default off, documented.
- **R4 Pre-auth key expires or is single-use** → resolved: prompted at run time, needed only for a join.
- **R5 Phone/tablet at home lose LAN while `tailscale01` is down and the app is on** → accepted, documented in S7.
- **R6 `deploy-targets.sh` warns about the created guest** → accepted, warning only, fixture-proven and documented.
- **`tailscale debug prefs` is a debug interface** → its shape may change between releases; the fixture pins the fields the role reads, and a changed shape shows up as a `set` on every rerun (the `changed=0` check catches it).
- **The stub proves the role's decisions, not Tailscale's** → real join, approval and SNAT are only in the post-merge checklist.

## Migration Plan

This order is the post-merge runbook in `docs/tailscale-subnet-router.md` (unit 3), with its ⚠ steps marked there.

1. Merge the PR after Gate 2 (CI green). Rue edits the tailnet policy first.
2. Runner plans one new LXC; Rue approves `infrastructure`; apply creates `tailscale01`; the deploy job logs the expected warning.
3. Rue fetches the inventory, creates a tagged pre-auth key and runs the operator playbook from the workstation, pasting the key.
4. Second run with an empty prompt: `changed=0`. Clients per checklist, then the Done checks.

Rollback: remove the `tailscale01` entry in a PR (runner destroys the LXC) and delete the node in the admin console. No other guest is affected.

## Open Questions

None.
