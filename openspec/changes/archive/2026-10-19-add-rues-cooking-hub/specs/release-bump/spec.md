## ADDED Requirements

### Requirement: Rues-Cooking-Hub releases trigger the bump

Rues-Cooking-Hub's `release.yml` SHALL call the reusable workflow for `rues_cooking_hub_version` in `ansible/inventory/host_vars/rues-cooking-hub01/vars.yml` (app `rues-cooking-hub`). This repo SHALL hold that variable on exactly one plain `rues_cooking_hub_version: vX.Y.Z` line once this change is on `main`. A release tagged before then fails its bump job on the missing file, which is accepted and not repaired.

#### Scenario: The pin line is bumpable
- **WHEN** `ansible/inventory/host_vars/rues-cooking-hub01/vars.yml` is read on the branch
- **THEN** it has exactly one line matching `^rues_cooking_hub_version: `, with the unquoted value `v0.1.0` and no trailing comment
- **proof:** manual (one-shot `rg -c` recorded in `verification.md`; `scripts/bump-pin.sh` lives in `Rue-Asha/ci` and is not run here)

#### Scenario: A release after the merge opens a bump PR
- **WHEN** `publish` succeeds for a Rues-Cooking-Hub tag newer than the pin and this change is on `main`
- **THEN** the `bump` job opens `chore(rues-cooking-hub): bump to <tag>` changing only `rues_cooking_hub_version`, which merges and deploys `02_SERVICES/rues-cooking-hub.yml` like Life-Manager's
- **proof:** manual (needs a real tag after the merge)

#### Scenario: The first release's bump fails before the merge
- **WHEN** the bump runs for `v0.1.0` while `rues-cooking-hub01/vars.yml` is missing on `main`
- **THEN** the script exits non-zero with `bump-pin: <file>: file not found` naming it, the job fails, and nothing in this repo changes (accepted)
- **proof:** manual (observed on the `v0.1.0` release run; the script behaviour is covered by the existing unit "Scenario: The file is not on main yet")
