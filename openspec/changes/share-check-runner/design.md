## Context

`check01` (vmid 226) runs one repository runner for `Homelab-Managment`, under
the user `check-runner` and the unit `check-runner.service`. The `check_runner`
role registers it with a token passed by hand as `-e`. `Rue-Asha` is a
personal GitHub account: runners can only be registered per repository, and
there are no runner groups. `Life-Manager` and `Rues-Arcade` run their PR
check (`ci.yml` → job `ci`) on `ubuntu-24.04`. Their `release.yml` reuses that
same `ci.yml` through `workflow_call` to build the release tarball. All repos
are public.

## Goals / Non-Goals

**Goals:**
- One host, one role and one list cover the PR checks of every homelab-deployed repo.
- Adding a repo takes one list entry and one playbook run, with no click-through for tokens.
- One repo's PR code can't touch another repo's runner, and the box still holds no credential.

**Non-Goals:** see proposal (org migration, ephemeral/JIT, release builds,
`security-baseline`, deploy runner).

## Decisions

**D1: N repository runners on one host, not an org and not a GitHub App.**
GitHub doesn't offer shared runners on a personal account, so per-repo
registration is fixed. The change automates it. *Org:* one registration in a
runner group, but every repo transfers, URLs change and the user Pages site
breaks. *GitHub App + JIT:* clean box per job, but an App key in the homelab
and a controller to run. That is the upgrade path if persistence becomes the
problem, and it was already named in `add-check-runner` D2.

**D2: One unix user, directory and unit per repo.** A single user with N runner
directories would let a PR in repo A poison repo B's `_work/_tool` and caches,
or read B's `.credentials`. A separate user with a home at `0700` turns that
into a permission error. Each instance costs about 300 MB of disk for the
runner release plus the repo's own tool cache. The root-owned toolchain
(`/usr/local/bin`, `/opt/check-runner/venv`) stays shared.

**D3: Naming is derived from the repo, not configured.** `Rue-Asha/Life-Manager`
becomes slug `life-manager`, user and unit `check-runner-life-manager`, and
runner name `check01-life-manager`. List entries carry only `repo`. An
assert rejects duplicate slugs.

**D4: Token minted on the controller, per unregistered instance.**
`gh api -X POST repos/<repo>/actions/runners/registration-token --jq .token`,
`delegate_to: localhost`, `become: false`, `no_log: true`. It only runs when
the instance has no `.runner` file, and it is skipped in check mode. The token
reaches `check01` only as an argv to `config.sh`, which is the same exposure the
`-e` token had. Prerequisite: `gh auth status` on the workstation, with admin on
each repo. `-e check_runner_registration_token` goes away. One way, not two.

**D5: Fork-approval policy is asserted, never set.** `gh api
repos/<repo>/actions/permissions/fork-pr-contributor-approval --jq
.approval_policy`. It is read-only, runs in check mode too and is asserted
equal to `all_external_contributors`, with no `no_log` so the `fail_msg`
names the repo. Changing GitHub settings from a playbook would be a side
effect hidden in a config run.

**D6: Per-instance job hook.** Each instance's workspace path differs
(`_work/<repo>/<repo>`), so every instance gets its own root-owned hook under
`/usr/local/lib/check-runner/<slug>-job-started.sh`, wired through its own
`.env`.

**D7: Dropping a repo stops and disables its unit only.** A `find` over
`/etc/systemd/system/check-runner-*.service` for slugs not in the list. Deleting
the GitHub registration needs a different API call and a decision, so the
runbook does it (`gh api -X DELETE repos/<repo>/actions/runners/<id>`), together
with `userdel -r`. *Bigger:* full teardown in the role, which would touch
GitHub from a converge run.

**D8: Legacy single instance is removed by the role.** A `legacy.yml` stops and
disables `check-runner.service`, removes the unit file and removes the
`check-runner` user with its home. The `Homelab-Managment` entry then
registers fresh as `check01-homelab-managment`. The old GitHub registration
shows offline and is deleted by hand once (runbook). The task file stays until
a later cleanup, because it is a no-op once the user is gone.

**D9: Playwright system libraries as a pinned apt list.** Jobs have no sudo,
so `npx playwright install --with-deps` can't work there. The role installs
`check_runner_browser_packages`. That is the list `npx playwright install-deps
--dry-run chromium` prints for Debian 13, captured once during implementation.
Jobs run `npx playwright install chromium` (browser into the instance's cache,
matching the repo's lockfile). *Bigger:* bake browsers per Playwright version,
which would couple the host to every repo's lockfile.

**D10: App repos split the check from the release via a reusable gate.** Both
app repos move the body of today's `ci` job into `.github/workflows/gate.yml`
(`workflow_call`, input `runner` as a JSON label list, `runs-on: ${{
fromJSON(inputs.runner) }}`). `ci.yml` calls it with `["self-hosted",
"homelab-check"]`, `release.yml` with `["ubuntu-24.04"]`. One job body, and the
tarball is still built and tested on hosted runners. The required check name
then becomes `ci / ci` (caller/called job). The branch ruleset is updated in
the same sitting. `workflow-triggers.py` lives only in this repo, so the
expression in `runs-on` is allowed there.

**D11: Capacity.** `check01` grows to 4 cores, 16384 MB memory and 32 GB disk.
Each instance runs one job at a time, so three repos mean at most three
concurrent jobs. Playwright e2e is the heaviest of them.

## Contracts

- Variable: `check_runner_repos: [{repo: "Rue-Asha/<name>"}, …]`, in `group_vars/check_runner/vars.yml`. Initial entries: `Homelab-Managment`, `Life-Manager`, `Rues-Arcade`.
- Derived per entry: slug `<name | lower>`, user and unit `check-runner-<slug>`, home `/home/check-runner-<slug>` (`0700`), runner name `{{ inventory_hostname }}-<slug>`, hook `/usr/local/lib/check-runner/<slug>-job-started.sh`.
- Label: `homelab-check` on every instance. `runs-on: [self-hosted, homelab-check]` in every repo.
- Removed: `check_runner_registration_token`, `check_runner_repo_url`, `check_runner_user`/`_home`/`_dir`/`_service_name` as scalars.
- New: `check_runner_browser_packages` (role default).
- App repos: `gate.yml` input `runner` (string holding a JSON label list, e.g. `["ubuntu-24.04"]`).

## Risks / Trade-offs

- [Persistent instances can be poisoned within one repo] → same as `add-check-runner` D2: no secrets, no sudo, workspace wiped, PR review. JIT runners are the upgrade.
- [Workstation `gh` token has admin on all repos] → it already does. The playbook only mints registration tokens and reads one setting.
- [Required check rename in the app repos blocks merges] → update the ruleset in the same sitting as the gate PR; the runbook lists the exact name.
- [`check01` down blocks merges in three repos, not one] → per-repo one-line fallback in `docs/check-runner.md`.
- [Playwright apt list drifts with a Playwright upgrade] → a missing library fails the e2e step loudly. Fix by re-capturing the list.
- [Node host capacity for 4c/16 GB] → open question below, check before the apply.

## Migration Plan

1. PR here: role, group vars, docs, `check01` resources. Merge → the deploy workflow plans and applies the resize after approval.
2. Set fork-PR approval to "all external contributors" on `Life-Manager` and `Rues-Arcade` (check `Homelab-Managment` too).
3. Run `check_runner.yml --check --diff`, then for real. The legacy instance goes and three instances register. Delete the old offline `check01` runner on `Homelab-Managment`.
4. `Homelab-Managment` needs no workflow change (same label). Confirm `proof` is green on a PR.
5. PR per app repo: introduce `gate.yml`, `ci.yml` on `homelab-check`, `release.yml` on hosted. Update the ruleset's required check. Green on `check01` before merge.
6. Rollback: revert the app repo's `ci.yml` caller to `["ubuntu-24.04"]`. For the host, re-run the previous role version (the old registration needs a fresh token).

## Open Questions

- Does `proxmox1` have 4 cores / 16 GB to spare for `check01` next to the other guests? Otherwise stay at 2c/4 GB and accept queueing.
- Exact required-check name the app repos' rulesets use today (`ci` vs `ci / ci`). Read before step 5.
