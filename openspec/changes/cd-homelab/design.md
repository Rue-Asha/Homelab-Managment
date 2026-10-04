## Context

`ci-homelab` made GitHub Actions the merge authority for `main`: `proof.sh
--all` plus the security baseline, on GitHub-hosted runners, with no secrets
and no route into the homelab. Life-Manager ships a checksummed, attested
release tarball per tag, and (once `feat/life-manager-release-artifact` is
merged) `life-manager01` deploys that tarball by fetching it itself with
`get_url`. A deploy is still a human running `ansible-playbook` from the
workstation, using `~/.ssh/Proxmox` and `~/.config/homelab/vault_pass`.

Constraints:
- GitHub-hosted runners cannot route to `192.168.0.0/24`.
- The repo is public and lives on a **user** account: no runner groups, so a
  repository runner accepts any job on this repo that names its labels.
- Actions logs on a public repo are world-readable.
- The fork-PR approval policy is currently `first_time_contributors`.

## Goals / Non-Goals

**Goals:**
- Merge to `main` = deploy, for every `03_SERVICES` playbook the merge affects.
- The runner only ever executes workflow code that is already on `main`.
- A deploy that breaks a service undoes itself and goes red.
- No GitHub secrets; deploy credentials never leave `runner01`.

**Non-Goals:**
- Automating `terraform apply` or `02_BASE_CONFIGURATION`.
- Automated version-bump PRs from Life-Manager releases.
- Moving tests or builds onto the self-hosted runner.
- Multi-environment (staging) promotion.

## Decisions

### D1 — Self-hosted repository runner, not pull-based or a tunnel

A runner on `runner01` connects out to GitHub; nothing inbound is opened.
*Alternatives:* `ansible-pull` on a timer (no deploy status in GitHub,
polling delay, failures happen silently); a cloud runner joining Tailscale
(needs a long-lived LAN credential stored as a GitHub secret, which breaks
"no secrets"). A private trigger repo holding the runner was the strictest
option. It is not adopted: D2 already makes the runner unreachable from
untrusted events, and the extra repo would add a cross-repo token. The
private-repo option stays the escape hatch if this repo ever takes outside
contributors.

### D2 — Trust boundary is the trigger, enforced by `proof.sh`

`deploy.yml` triggers only on `push: main` and `workflow_dispatch`, and the
`production` environment allows only `main`, so a dispatch on a feature branch
never reaches the runner. That protects against our own mistakes. The attack
it doesn't cover is a fork PR that edits a workflow to add
`runs-on: self-hosted`. Two layers stop that:
1. Fork-PR approval set to **all external contributors**, so no fork code
   runs without a click.
2. A new `proof.sh` sensor fails any workflow that mixes untrusted triggers
   (`pull_request`, `pull_request_target`, `issues`, `issue_comment`, …) with
   a `self-hosted` runner. It runs from CI on GitHub-hosted runners, so it
   catches the mistake in our own PRs before merge.

The runner also carries a distinct `homelab-deploy` label, so no generic
`self-hosted` job lands on it by accident.

### D3 — Credentials live on the runner, injected via the runner's `.env`

The runner reads `<runner dir>/.env` at start and passes it to every job.
The `github_runner` role writes:

```
ANSIBLE_PRIVATE_KEY_FILE=/home/github-runner/.ssh/deploy_ed25519
ANSIBLE_VAULT_PASSWORD_FILE=/home/github-runner/.config/homelab/vault_pass
ANSIBLE_HOST_KEY_CHECKING=True
ANSIBLE_SSH_ARGS=-o UserKnownHostsFile=/home/github-runner/.ssh/known_hosts -o ControlMaster=auto -o ControlPersist=60s
```

Environment variables override `ansible.cfg`, so the repo config keeps
working unchanged on the workstation. The workflow contains no credentials
and no `secrets.*`. *Alternative:* GitHub environment secrets, rejected
because it would put a LAN key in GitHub and contradict `ci-pipeline`.

The deploy key pair is generated on `runner01` by the role. Its public half is
fetched back to the controller and authorised for the `ansible` user on
`proxmox_guest` hosts through `guest_bootstrap`, as a second key next to the
workstation key. `proxmox_node` never receives it. Deploys also pass
`--limit 'proxmox_guest'` as a second guard.

### D4 — Host keys pinned at bootstrap, by a human-run playbook

The `github_runner` role builds `known_hosts` by `ssh-keyscan`-ing every
`proxmox_guest` host while the role runs. The role is only ever run by a
human (D6), so trust-on-first-use happens on the human's run, never inside a
deploy. Cost: a new or recreated guest fails its first deploy until the runner
playbook is re-run. That failure is deliberate, because a silently changed
host key is exactly what this is meant to catch.

### D5 — Change-to-playbook mapping in `scripts/deploy-targets.sh`

The script takes `<before> <after>` (or `--all`, or a playbook name) and prints
the affected `03_SERVICES` playbooks, one per line. For each playbook it
derives:
- **roles**: the play's `roles:` list. The `03_SERVICES` playbooks are
  declarative (single play, `roles:` list), so reading the YAML is enough.
  Nested role dependencies come from each role's `meta/main.yml`, followed
  transitively.
- **hosts and groups**: from `ansible-playbook --list-hosts` and
  `ansible-inventory --graph`, resolved against the real inventory, so
  `group_vars/<group>` maps to every playbook with a host in that group.

`ansible.cfg` or `collections/requirements.yml` changing, or a `before` that is
all zeros or not an ancestor of `after`, maps to every playbook. A deleted
playbook is skipped. The script reuses `proof.sh`'s conventions: run from the
repo root, `ANSIBLE_CONFIG` defaulted. It runs locally with no homelab access
(inventory and YAML parsing only), so the mapping can be tested in CI with
fixtures.

*Alternative:* a hand-written path→playbook table (e.g. `dorny/paths-filter`).
It would be simpler, but it rots: every new service or shared role means
another edit, and forgetting one means a silent non-deploy.

### D6 — The runner never manages itself

The runner's playbook is
`ansible/playbooks/02_BASE_CONFIGURATION/deploy_runner.yml`, applying
`common`, an `egress_firewall` role and `github_runner`. It is outside
`03_SERVICES`, so `deploy-targets.sh` never selects it. A deploy that
restarted or re-registered its own runner would kill the job mid-run.
Following the repo rule that host-level concerns stay out of service roles,
the firewall is its own `egress_firewall` role (nftables, default-drop output)
with a variable listing the allowed destinations. It can be reused by other
guests later.

### D7 — Persistent runner, workspace cleaned per job, not ephemeral

`--ephemeral` makes the runner deregister after each job. Re-registering
needs a fresh registration token, which in turn needs a PAT with repo admin
rights stored on `runner01`. That would be a worse credential than anything
the runner holds today. Because D2 means only `main`'s code runs here, a
persistent runner with `actions/checkout` `clean: true` and an explicit
workspace wipe is enough.
*What the bigger design would buy:* a disposable job container (e.g. a
container per job via the runner's container hooks) would contain a
compromised job. Revisit if D2's assumptions change.

The registration token is obtained by hand
(Settings → Actions → Runners → New) and passed once as an extra var to the
bootstrap run, with `no_log`. It expires in an hour and is never stored.

### D8 — Smoke check and rollback inside the service role

`life_manager` gains `tasks/verify.yml`, imported last:
1. Record the pre-run `current` target (before `release.yml` swaps it) as
   `life_manager_previous_release`. This uses a new variable name, never
   `set_fact` over a default.
2. `meta: flush_handlers`, so the restart has happened.
3. In a `block`: `ansible.builtin.uri` against `http://127.0.0.1/` on the host
   (through nginx, so proxy and app are both checked), `until` 2xx, with
   bounded `retries`/`delay` as role defaults.
4. `rescue`: if a previous release exists and differs from the new one,
   repoint `current` and restart. Then `ansible.builtin.fail` naming both
   releases.

Running it in the role rather than in the workflow means a manual
`ansible-playbook` run gets the same safety net. Rollback is the existing
symlink model; no new state is needed.

### D9 — Deploy workflow shape

```
on: push(main) | workflow_dispatch(playbook: choice incl. "all")
permissions: contents: read
concurrency: { group: deploy-production, cancel-in-progress: false }
jobs:
  deploy:
    runs-on: [self-hosted, homelab-deploy]
    environment: production
    steps: checkout (persist-credentials: false, fetch-depth: 0)
           → ansible-galaxy collection install (pinned)
           → scripts/deploy-targets.sh  → for each: ansible-playbook <pb> --limit proxmox_guest
```

Playbooks run sequentially. The first failure stops the job, and the
remaining playbooks are listed in the log as not run. No `--diff`, no `-v`.
Ansible itself is installed on the runner by the role, pinned to the
version in `ci/requirements.txt`, so deploys use the same ansible-core that
CI linted against.

The ruleset on `main` must require branches to be up to date before merging,
so the commit that deploys is the commit CI tested. Without that, two PRs that
are each green can merge into an untested combination.

## Risks / Trade-offs

- [A fork PR's workflow reaches the runner] → approval for all external
  contributors + `proof.sh` trigger sensor + `production` branch policy;
  Private-trigger-repo fallback documented in D1.
- [Compromised dependency (action, collection, pip package) runs on the
  runner] → actions SHA-pinned (existing baseline), collections and
  ansible-core pinned exactly; egress firewall keeps the runner off the
  Proxmox node and off the LAN except guest SSH.
- [Deploy key is effectively sudo on every guest] → scoped to `ansible` on
  guests, never the node; file mode 0600 owned by `github-runner`; runner has
  no sudo. Rotating it means re-running the runner and bootstrap playbooks.
- [Secrets leak into public logs] → no `--diff`/`-v`, `no_log` audit on
  secret-bearing tasks. Today `env.j2` holds no secret, but the rule holds
  for the first one that does.
- [Migrations are forward-only, so rollback restores old code onto a migrated
  DB] → accepted for now; Life-Manager migrations must stay additive. Noted in
  the role README.
- [Runner down → merges silently don't deploy] → the job sits in `queued`
  and fails after GitHub's 24 h limit; GitHub shows the deployment as
  pending. Acceptable for a single-user homelab.
- [Smoke check only proves `/` answers 2xx] → cheap and catches crash-on-start
  and bad migrations, which are the realistic failures. A real health endpoint
  can replace the URL later via a role default.

## Migration Plan

1. Merge `feat/life-manager-release-artifact`.
2. On a feature branch: add `runner01` to `hosts.auto.tfvars`, then **manual**
   `terraform apply` (regenerates the inventory), and bootstrap it with
   `02_BASE_CONFIGURATION/bootstrap.yml`.
3. Run `deploy_runner.yml` by hand with the registration token. The runner
   shows as idle on the repo.
4. Re-run `bootstrap.yml` on the guests to authorise the deploy key.
5. Change GitHub settings: fork approval policy, the `production` environment
   (branch policy `main`), and "require branches up to date" on the ruleset.
6. Merge the PR containing `deploy.yml`. Its own merge changes
   `life_manager` role files, so the first real deploy is `life-manager.yml`
   with the smoke check in place.
7. Prove rollback once: deploy a deliberately broken version via a throwaway
   bump, confirm it goes red and `current` is back on the old release, then
   revert the bump.

Rollback of the change itself: disable the `deploy` workflow in the Actions
UI (or delete `deploy.yml`). The runner stays idle and manual deploys keep
working, because `ansible.cfg` is untouched.

## Open Questions

- Should `runner01` be an LXC (cheaper, matches everything else) or a VM
  (stronger isolation from the Proxmox kernel)? Default: LXC, unprivileged.
- Retry budget for the smoke check. Default 10 × 3 s, assuming Life-Manager's
  start-up migrations finish within 30 s.
