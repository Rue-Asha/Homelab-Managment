## Why

Rue releases an app by tagging it, then has to hand-edit the pinned `*_version` line in this repo, open a PR and merge it before anything deploys. The edit is mechanical and easy to forget.

## What Changes

- New reusable workflow in `Rue-Asha/ci` (`bump-pin.yml`, plus a `scripts/bump-pin.sh` it runs): sets a pinned version variable to a release tag in this repo, opens a PR as a GitHub App, closes superseded bump PRs, enables auto-merge.
- `release.yml` in Life-Manager and Rues-Arcade gets a `bump` job after `publish`. Rues-Arcade is blocked on PR #23.
- This repo: `allow_auto_merge` switched on by Rue; `docs/release-bump.md` documents flow, App setup and recovery. No change to `ci.yml`, `deploy.yml`, `deploy-targets.sh`.
- The existing `main` ruleset (PR required, 0 reviews, four required checks, strict) stays as is; see design, "Scope corrections".

## Capabilities

### New Capabilities
- `release-bump`: a tagged app release becomes a pin-bump PR in this repo that merges itself after CI and deploys through the existing `deploy.yml`.

### Modified Capabilities
<!-- none: continuous-deployment and ci-pipeline requirements are unchanged; they are relied on, not edited -->

## Non-Goals

- `pihole_version` and other upstream pins (Renovate would be the tool; split off).
- `github_runner_version`; the runner is configured by hand on purpose.
- Bumping several variables in one PR, or batching releases.
- Creating the GitHub App or changing repo settings from an agent; Rue does both.
- A Homelab CI check that a bot PR only touches the pin line (accepted gap, R2).
- Pre-release tags deploying (the bump skips them).
- Fixing the pin/host mismatch after a rolled-back deploy (existing behaviour, R3).

## Done criteria

- [ ] Tagging a Life-Manager release produces a green bump PR in Homelab-Managment that merges itself and deploys, with no hand edit.
- [ ] A re-run of the bump job for the same tag does nothing and does not fail.
- [ ] The first real release confirms R1: `deploy.yml` runs after the auto-merge.
- [ ] After #23 is merged, the same holds for a Rues-Arcade release.
- [ ] `docs/release-bump.md` lets Rue set up a third app without asking.
- [ ] `scripts/proof.sh --all` is green.

## Appetite

One evening, plus the Rues-Arcade hookup after PR #23 is merged. Exceeding it means renegotiating scope.

## Impact

- `Rue-Asha/ci`: new workflow, script, fixture tests; new release tag.
- `Rue-Asha/Life-Manager`, `Rue-Asha/Rues-Arcade`: `.github/workflows/release.yml`.
- This repo: `docs/release-bump.md`, repo settings (manual). Risks R1-R6 from scope.md apply; R2 and R3 accepted.
