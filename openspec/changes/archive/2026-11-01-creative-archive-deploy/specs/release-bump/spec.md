## ADDED Requirements

### Requirement: Creative-Archive releases trigger the bump

Creative-Archive's `release.yml` SHALL call the reusable workflow for `creative_archive_version` in `ansible/inventory/host_vars/creative-archive01/vars.yml` (app `creative-archive`). This repo SHALL hold that variable on exactly one plain `creative_archive_version: vX.Y.Z` line, unquoted and without a trailing comment, once this change is on `main`, starting at `v0.1.0`. A release tagged before then fails its bump job on the missing file, which is accepted and not repaired.

#### Scenario: The Creative-Archive pin line is bumpable
- **WHEN** `ansible/inventory/host_vars/creative-archive01/vars.yml` is read on the branch
- **THEN** it has exactly one line matching `^creative_archive_version: `, with the unquoted value `v0.1.0` and no trailing comment
- **proof:** manual (one-shot `rg -c` recorded in `verification.md`; `scripts/bump-pin.sh` lives in `Rue-Asha/ci` and is not run here)

#### Scenario: A Creative-Archive release after the merge opens a bump PR
- **WHEN** `publish` succeeds for a Creative-Archive tag newer than the pin and this change is on `main`
- **THEN** the `bump` job opens `chore(creative-archive): bump to <tag>` changing only `creative_archive_version`, which merges and deploys `02_SERVICES/creative-archive.yml` like Life-Manager's
- **proof:** manual (needs a real tag after the merge)

#### Scenario: The first Creative-Archive bump fails before the merge
- **WHEN** the bump runs for `v0.1.0` while `creative-archive01/vars.yml` is missing on `main`
- **THEN** the script exits non-zero with `bump-pin: <file>: file not found` naming it, the job fails, and nothing in this repo changes (accepted); once the change is merged the pin already equals `v0.1.0`, so a re-run prints `unchanged`
- **proof:** manual (observed on the `v0.1.0` release run; the script behaviour is covered by the existing unit "Scenario: The file is not on main yet")
