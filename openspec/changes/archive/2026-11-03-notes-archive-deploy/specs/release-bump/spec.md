## ADDED Requirements

### Requirement: Notes-Archive holds a bumpable pin

This repo SHALL hold `notes_archive_version` in `ansible/inventory/host_vars/notes-archive01/vars.yml` on exactly one plain `notes_archive_version: vX.Y.Z` line, unquoted and without a trailing comment, starting at `v0.1.0`, and `docs/release-bump.md` SHALL list app `notes-archive` with that variable and file under "Wired-up apps". Notes-Archive's `release.yml` calling the reusable workflow is the split-off change in the app repo; until it lands, no bump runs. A tag equal to the pin produces no bump PR, so that release is deployed by the manual dispatch.

#### Scenario: The Notes-Archive pin line is bumpable
- **WHEN** `ansible/inventory/host_vars/notes-archive01/vars.yml` is read on the branch
- **THEN** it has exactly one line matching `^notes_archive_version: `, with the unquoted value `v0.1.0` and no trailing comment
- **proof:** manual (one-shot `rg -c` recorded in `verification.md`; `scripts/bump-pin.sh` lives in `Rue-Asha/ci` and is not run here)

#### Scenario: docs/release-bump.md lists Notes-Archive
- **WHEN** `rg -n 'notes_archive_version' docs/release-bump.md` runs
- **THEN** it finds the row `notes-archive` · `notes_archive_version` · `ansible/inventory/host_vars/notes-archive01/vars.yml` under "Wired-up apps", after the `creative-archive` row
- **proof:** manual (one-shot command recorded in `verification.md`)

#### Scenario: A Notes-Archive release after the split-off opens a bump PR
- **WHEN** the app repo's `release.yml` (split-off change) publishes a tag newer than the pin and this change is on `main`
- **THEN** the `bump` job opens `chore(notes-archive): bump to <tag>` changing only `notes_archive_version`, which merges and deploys `02_SERVICES/notes-archive.yml` like Creative-Archive's
- **proof:** manual (needs the split-off release workflow and a real tag after the merge)

#### Scenario: A first tag equal to the pin bumps nothing
- **WHEN** the bump runs for `v0.1.0` while the pin already reads `v0.1.0`
- **THEN** the script prints `unchanged` and opens no PR; the release is deployed by dispatching `deploy.yml` with playbook `notes-archive` (runbook step 7)
- **proof:** manual (needs the split-off release workflow and the real `v0.1.0` run; the `unchanged` result without a PR is the existing unit "Scenario: The value already equals the tag")
