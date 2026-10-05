# Scope: auto-version-bump

Triage: feature — cross-repo CI/deploy change, GitHub App, repo settings. Appetite: one evening (+ the Rues-Arcade hookup after PR #23 is merged).

## Problem
Rue releases an app by tagging it, then has to hand-edit the pinned `*_version` line in this repo, open a PR and merge it before anything deploys. The edit is mechanical and easy to forget.

## Flows
- Release: tag `vX.Y.Z` in an app repo → `release.yml` check-tag → gate → publish → **bump job** → PR in Homelab-Managment → CI → auto-merge → `deploy.yml` deploys the service playbook → smoke check (rollback on failure).
- One-time setup: Rue creates the GitHub App, installs it on Homelab-Managment, adds app id/key to the app repos, and enables auto-merge + branch protection here.

## In scope
- **S1** A reusable workflow in `Rue-Asha/ci` takes `(app repo token inputs, host_vars path, variable name, tag)`, sets that variable to the tag in a checkout of Homelab-Managment, pushes branch `bump/<variable>-<tag>` and opens a PR titled `chore(<app>): bump to <tag>` with the repo's conventional-commit format.
  - edges: variable line missing → job fails with the file and variable named; value already equals the tag (re-run) → no-op, job succeeds; branch or PR for that tag already exists → no-op, job succeeds; tag has a pre-release suffix (`-rc1`) → no bump.
- **S2** The PR is opened with a GitHub App installation token, so `ci.yml` runs on it.
  - edges: app lacks access → job fails loudly rather than falling back to `GITHUB_TOKEN`.
- **S3** When a newer bump PR for the same variable is opened, still-open older ones are closed.
  - edges: older PR already merged → nothing to close.
- **S4** The bump PR is merged automatically once CI is green (`gh pr merge --auto --squash`), and the merge triggers `deploy.yml`.
  - edges: CI red → PR stays open, nothing deploys; deploy smoke check fails → existing rollback applies, the pin on `main` then names a version the host doesn't run (accepted, see R3).
- **S5** Life-Manager's `release.yml` calls the reusable workflow after `publish` for `life_manager_version` in `host_vars/life-manager01/vars.yml`.
  - edges: `publish` fails → bump job doesn't run (`needs: publish`).
- **S6** Rues-Arcade's `release.yml` calls it the same way for `rues_arcade_version` in `host_vars/rues-arcade01/vars.yml`. **Blocked on PR #23 being merged**; goes last and doesn't hold up S1–S5.
  - edges: file not on `main` yet → job fails on the missing file (S1 edge), so S6 is only merged after #23.
- **S7** Repo settings on Homelab-Managment: `allow_auto_merge` on and branch protection on `main` requiring the CI checks (`proof`, `security-baseline`), no required reviews. Rue applies these by hand; the change documents the exact settings.
  - edges: none (settings only).
- **S8** `docs/release-bump.md` describes the flow, the GitHub App setup (permissions, secrets per app repo), how to add a new app, and what to do when a bump PR is red.
  - edges: none (documentation).

## Non-goals
- `pihole_version` and other upstream pins — Renovate would be the tool; not this change.
- `github_runner_version` — the runner is configured by hand on purpose.
- Bumping several variables in one PR, or batching releases.
- Creating the GitHub App or changing repo settings from the agent — Rue does that.
- A Homelab CI check that a bot PR only touches the pin line — accepted gap, see R2.
- Pre-release tags deploying (S1 skips them).
- Fixing the pin/host mismatch after a rolled-back deploy — existing behaviour.

## Codebase touchpoints
- `ansible/inventory/host_vars/life-manager01/vars.yml` — `life_manager_version`, line the job edits (explorer: pins)
- `ansible/inventory/host_vars/rues-arcade01/vars.yml` — `rues_arcade_version`; exists only on `feat/rues-arcade` (explorer: PR #23)
- `scripts/deploy-targets.sh` — already maps a `host_vars/<host>` change to its playbook; no change expected (explorer: mapping)
- `.github/workflows/ci.yml` — `pull_request` to `main` runs `proof` and `security-baseline`; no change expected (explorer: CI)
- `.github/workflows/deploy.yml` — push to `main`; no change expected, but must fire after an auto-merge (R1)
- `docs/release-bump.md` — new
- `Rue-Asha/ci` (`.github/workflows/`) — new reusable workflow; today has `security-baseline.yml`, `self-check.yml` (checked via gh)
- `Rue-Asha/Life-Manager`, `Rue-Asha/Rues-Arcade` `.github/workflows/release.yml` — tag `v*` → check-tag → gate → publish; bump job appended

## Risks
- R1 Does a merge performed by auto-merge trigger `deploy.yml`? Pushes by `GITHUB_TOKEN` don't trigger workflows; an App-initiated auto-merge should → accepted: verified on the first real release, listed in Done when.
- R2 Auto-merge means a compromised app repo or App key can deploy to the homelab by editing one line, via the self-hosted runner → accepted: the App can only write to this one repo, the diff is a one-line pin, and `deploy.yml`'s `infrastructure` approval still gates Terraform. Rue chose auto-merge knowingly.
- R3 A rolled-back deploy leaves the pin ahead of the host → accepted: matches today's behaviour with manual bumps.
- R4 Main is not protected and `allow_auto_merge` is off today (checked via gh), so `--auto` can't work yet → resolved by S7, applied by Rue before S4 is tested.
- R5 Rues-Arcade's `rues_arcade` role might not have the same smoke-check/rollback as `life_manager`, which auto-merge leans on → spike: planner checks `verify.yml` on `feat/rues-arcade` as part of S6; if it lacks rollback, S6 is cut to manual merge for that app.
- R6 A reusable workflow in `Rue-Asha/ci` is only callable from other repos if the repo's access settings allow it → planner checks, and S7 lists the setting if needed.

## Decisions
- GitHub App, not a PAT — Rue's choice: not tied to the account, scoped to one repo.
- Auto-merge, not manual merge — Rue's choice, with R2 accepted. The manual merge was the recommended default; the agent flagged that every tagged release now deploys on its own.
- Reusable workflow in `Rue-Asha/ci`, not per-repo copies — two apps exist (and PR #23 is open), so one copy is cheaper to maintain.
- Scope is Life-Manager + Rues-Arcade; Rues-Arcade connected last because PR #23 isn't merged.
- Branch per tag (`bump/<variable>-<tag>`), older open PRs closed — avoids force-pushes to a bot branch.

## Done when
- Tagging a Life-Manager release produces a green bump PR in Homelab-Managment that merges itself and deploys, with no hand edit.
- A re-run of the bump job for the same tag does nothing and doesn't fail.
- The first real release confirms R1: `deploy.yml` runs after the auto-merge.
- After #23 is merged, the same holds for a Rues-Arcade release.
- `docs/release-bump.md` lets Rue set up a third app without asking.
- `scripts/proof.sh --all` is green.

## Split off
- Renovate for `pihole_version` and other upstream pins.
