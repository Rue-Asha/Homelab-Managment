# Release bump

Tagging an app release bumps its pin here by itself. The app repo's
`release.yml` calls the reusable workflow `Rue-Asha/ci/.github/workflows/bump-pin.yml`,
which sets the app's `*_version` variable to the tag, opens a PR in this repo
as a GitHub App, and turns on auto-merge. `ci.yml` runs on the PR, GitHub merges
it when green, and the merge deploys through the unchanged `deploy.yml`
(see `docs/deploy-runner.md`). This page covers the flow, the App and repo
setup, adding an app, and recovering a PR that does not merge.

## The flow

1. Tag `vX.Y.Z` in the app repo. `release.yml` runs `check-tag`, the gate and
   `publish`.
2. The `bump` job (`needs: publish`) calls `bump-pin.yml`. It mints an
   installation token for the App, checks out this repo, and runs
   `scripts/bump-pin.sh <host_vars_path> <variable> <tag>` from `Rue-Asha/ci`.
   Only the value on the line `^<variable>: ` changes (quotes and a trailing
   comment stay); the rest of the file is byte-identical.
3. On `changed` (`scripts/ensure-bump-pr.sh`) it pushes branch `bump/<variable>-<tag>`, opens a PR titled
   `chore(<app>): bump to <tag>` (the commit message is the same line), runs
   `gh pr merge --auto --squash`, and closes older open `bump/<variable>-*`
   PRs with a comment naming the new one.
4. `ci.yml` runs on the PR. When the four required checks pass, GitHub
   squash-merges it.
5. The merge to `main` starts `deploy.yml`, which maps the changed host_vars
   file to the service playbook and runs it. The role's smoke check and
   rollback apply as for any deploy.

The job ends green without a PR when:

| Case | Script output |
|---|---|
| Tag has a pre-release suffix (`v1.2.3-rc1`) | `skipped` |
| The variable already equals the tag (re-run) | `unchanged` |
| The PR for `bump/<variable>-<tag>` is merged, or open with auto-merge on | nothing created |

A re-run finishes what a failed run left: a branch without a PR gets its PR, a
PR without auto-merge gets auto-merge, a still-open older bump PR is closed. A PR closed without merging is left
alone (tag again to bump).

It fails when the variable line is missing (`bump-pin: <file>: <variable> not found`),
when its value is empty, templated or not a bare or simply quoted token
(`bump-pin: <file>: <variable> has no plain or quoted value`), when the tag is
not a safe plain YAML scalar (whitespace, `#`, quotes, `{}[],`, backslash,
trailing `:`; `bump-pin: <tag>: not a safe YAML scalar`),
when the file is not on `main` yet (`bump-pin: <file>: file not found`), or when the
App token cannot be created. There is no fallback to `GITHUB_TOKEN`: a bump PR
opened by it would not trigger `ci.yml`.

## GitHub App

One App serves every app repo. Rue creates it by hand.

| Setting | Value |
|---|---|
| Installed on | `Rue-Asha/Homelab-Managment` only |
| Repository permissions | Contents: read and write, Pull requests: read and write, Metadata: read |
| Everything else | none |
| Webhooks | off |

Per app repo, under Settings > Secrets and variables > Actions:

| Secret | Value |
|---|---|
| `HOMELAB_BUMP_APP_ID` | the App's id |
| `HOMELAB_BUMP_APP_KEY` | the full contents of a generated private key (`.pem`) |

The caller passes them to the workflow explicitly as `app_id` and
`app_private_key`; `secrets: inherit` is not used. `Rue-Asha/ci` is public, so
other repos can call its workflows without any access setting.

Rotating the key: generate a new one in the App settings, update
`HOMELAB_BUMP_APP_KEY` in each app repo, then delete the old key.

## Repo setting

Enable auto-merge on this repo (Settings > General > Pull Requests > Allow
auto-merge), or:

    gh api -X PATCH repos/Rue-Asha/Homelab-Managment -F allow_auto_merge=true
    gh api repos/Rue-Asha/Homelab-Managment --jq .allow_auto_merge   # true

The `main` ruleset stays as it is: PR required, 0 approvals, squash allowed,
strict up-to-date policy, and the required checks

- `proof`
- `security-baseline / workflow-lint`
- `security-baseline / secret-scan`
- `security-baseline / dependency-review`

Without `allow_auto_merge`, `gh pr merge --auto` fails and the bump PR is left
open for a manual merge.

## Add an app

1. Make sure the app's pin is one `<variable>: <value>` line in a host_vars
   file in this repo, and that the service playbook is mapped by
   `scripts/deploy-targets.sh`.
2. Add `HOMELAB_BUMP_APP_ID` and `HOMELAB_BUMP_APP_KEY` to the app repo.
3. Add a job to the app's `release.yml` after `publish`, pinned to a full SHA
   of `Rue-Asha/ci` (the security baseline requires hash pins):

       bump:
         needs: publish
         permissions:
           contents: read
         uses: Rue-Asha/ci/.github/workflows/bump-pin.yml@<sha> # vX.Y.Z
         with:
           app: life-manager
           host_vars_path: ansible/inventory/host_vars/life-manager01/vars.yml
           variable: life_manager_version
           tag: ${{ github.ref_name }}
         secrets:
           app_id: ${{ secrets.HOMELAB_BUMP_APP_ID }}
           app_private_key: ${{ secrets.HOMELAB_BUMP_APP_KEY }}

   `app` names the PR title, `host_vars_path` is relative to this repo's root,
   `variable` is the pin's name. `target_repo` (`owner/name`) defaults to
   `Rue-Asha/Homelab-Managment` and needs no input; the App token is scoped to it.
4. If the app's host_vars file is not on `main` yet, merge it here first;
   otherwise the first bump fails on the missing file.

## When a bump PR does not merge

**Red check.** The PR stays open and nothing deploys. Open the failing check
from the PR. Fix the cause on `main` (or in the app repo and release a new tag),
then either re-run the check or tag again: the new bump closes the red PR.
Do not edit the bot's branch.

**Behind `main`.** The ruleset is strict, so another merge to `main` leaves
the bump PR out of date and auto-merge waits. Use "Update branch" on the PR
(`gh pr update-branch <n>`); CI re-runs and auto-merge continues. If it is
stale for good, tag a new release and let the cleanup supersede it.

**No PR appeared.** Check the `bump` job in the app repo's release run. A token
error means the App is not installed on this repo or the secrets are wrong. Re-running
the job for the same tag is safe: it only adds the PR or auto-merge that is missing.

**Deploy failed after the merge.** The role rolled back, but `main` now pins a
version the host does not run. Fix forward with a new release, or revert the
pin by hand in a PR.

## Accepted risks

- A compromised app repo or App key can deploy to the homelab by editing one
  pin line. The App writes only to this repo, and the `infrastructure`
  approval still gates Terraform.
- A rolled-back deploy leaves the pin ahead of the host, as it does with manual bumps.
