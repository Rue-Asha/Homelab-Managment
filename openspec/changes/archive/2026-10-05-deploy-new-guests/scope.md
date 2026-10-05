# Scope: deploy-new-guests

Triage: feature — changes what the deploy pipeline runs on `main`, and the follow-up is a live create. Appetite: one session.

## Problem
A merge that adds a guest only to `terraform/environments/homelab/hosts.auto.tfvars`
creates the LXC and pins its host key, but configures nothing. `scripts/deploy-targets.sh`
only diffs `ansible/`, so the new guest stays empty until some later change touches its
Ansible files. Rue hit this while preparing the `pihole01` rebuild.

## Flows
- New guest: PR adds a host to `hosts.auto.tfvars` → merge → plan → `infrastructure` approval →
  apply (creates guest, pins host key) → deploy renders the inventory → selects every
  `03_SERVICES` playbook whose hosts include the new guest → runs it → smoke check.
- Unchanged: a merge that touches only `ansible/` selects playbooks exactly as today.
- Unchanged: `workflow_dispatch` (`all`, `life-manager`) behaves as today.

## In scope
- **S1** The apply job reports the guests this apply created (the same set whose host keys
  `tf-ci.sh apply` pins) as a job output, and the deploy job hands that list to `deploy-targets.sh`.
  - edges: no `terraform/` change → apply skipped → empty list, deploy behaves as today ·
    apply creates nothing (update/destroy only) → empty list · apply fails → deploy does not run (as today)
- **S2** `deploy-targets.sh` treats each created guest like a changed host: every `03_SERVICES`
  playbook whose `--list-hosts` contains it is selected, merged and de-duplicated with the
  playbooks the `ansible/` diff already selects, in the existing order.
  - edges: created guest in no `03_SERVICES` playbook (e.g. a bare guest) → nothing extra selected, the
    run logs that the guest has no service playbook · created guest in `github_runner` → never selected
    (existing rule) · same playbook selected by diff and by a created guest → runs once ·
    unknown host name (not in the rendered inventory) → fails loudly, not silently skipped
- **S3** The fixture tests in `scripts/tests/deploy-targets.sh` cover S2 and its edges, and `proof.sh`
  runs them (already wired when the script or its tests change).
- **S4** Docs and spec say it: `docs/deploy-runner.md` (what a merge deploys), the
  `continuous-deployment` spec delta (a newly created guest gets its service playbooks in the same run).

## Non-goals
- Re-pinning the host key of a **recreated** guest (replace) — stays a deliberate manual step
  (`deploy_runner.yml`), as `docs/deploy-runner.md` documents; widening trust automatically is a separate decision.
- Running `02_BASE_CONFIGURATION/bootstrap.yml` for new guests — the golden template already carries the
  `ansible` user, keys and SSH hardening, and `03_SERVICES` playbooks run `common`.
- A `pihole` option for `workflow_dispatch` — not needed once creates deploy themselves.
- The `pihole01` rebuild itself — see Split off.

## Codebase touchpoints
- `.github/workflows/deploy.yml` — apply job output, deploy job passes it on (explorer: deploy path for a new guest; apply `:93-110`, deploy `:112-175`)
- `scripts/tf-ci.sh` — apply already loops over `create` actions for host-key pinning (`:220-237`); emit the names
- `scripts/deploy-targets.sh` — diff only covers `ansible/` (`:48`), `changed_hosts` (`:85`, `:152`); add created-host input
- `scripts/tests/deploy-targets.sh` — fixtures
- `docs/deploy-runner.md`, `openspec/specs/continuous-deployment/spec.md`

## Risks
- R1 The create path with an API-token-only runner has never run (archived golden-template design: create left for 6.3, closed with the destroy path only) → accepted: the split-off `pihole01` rebuild is the first live create and proves it.
- R2 Stale `.225` key in runner's `known_hosts` would make the rebuild's deploy fail → accepted: the rebuild checks `ssh-keygen -F 192.168.0.225` on runner01 before merging; the old pihole01 never got a key pinned.
- R3 GitHub job outputs are strings → resolved: pass a space-separated host list, host names are `[a-z0-9-]`.

## Decisions
- Source of "new guest" is the apply result, not a `hosts.auto.tfvars` diff — it reflects what was actually created and reuses the set the host-key pinning already computes (Rue, explore).
- Two PRs: this change first, the `pihole01` rebuild as its own change afterwards — a failed live create is then clearly not the fix's merge, and the rebuild is a clean create proof (Rue, explore).

## Done when
- `scripts/proof.sh --all` green, including new `deploy-targets.sh` fixtures for created guests.
- The PR's merge run deploys nothing it wouldn't have before (no guest created).
- The follow-up `pihole01` rebuild PR, which only adds tfvars + vault.yml, ends with `pihole.yml` run and its smoke check green in the same workflow run.

## Split off
- **rebuild-pihole01** (change, after this one ships): re-add `pihole01` to `hosts.auto.tfvars` with the removed block from `6be473d` (spec sizing), cherry-pick only `6cabf8e` (vault.yml; encrypted with the same `vault_pass` the runner holds — Rue confirmed), drop `bf4f8d9`, rewrite `docs/pihole.md` *First-time apply* / *Rebuild* / *Status* for the runner flow, pre-merge check of runner01 `known_hosts` for `.225`. Router fallback is already in place (Rue). Its run is the create proof the golden-template change left open.
