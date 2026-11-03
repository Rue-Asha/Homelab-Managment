# Split off: Notes-Archive CI and release workflow

Intent: the app repo gets the two workflows that this change's Homelab side expects. Not part of `notes-archive-deploy`; do it in Rue-Asha/Notes-Archive once `build-notes-archive` has landed on its `main`.

## Decisions already made
- Rue selected this at triage, then it was cut: other repo, app still mid-build on `flow/build-notes-archive` (35 open tasks), and it would have been a sixth S-item.
- The Homelab side expects (from `notes-archive-deploy` S2/S3):
  - asset `https://github.com/Rue-Asha/Notes-Archive/releases/download/<tag>/notes-archive-<version-without-v>.tgz` plus `.sha256` (`<hex>  <name>.tgz`), top-level dir `notes-archive-<version>/` containing `build/`, `migrations/`, `package.json`, production `node_modules`.
  - `release.yml` calls `Rue-Asha/ci/.github/workflows/bump-pin.yml@<sha>` with `app`, `host_vars_path: ansible/inventory/host_vars/notes-archive01/vars.yml`, `variable: notes_archive_version`, `tag`, and `secrets.HOMELAB_BUMP_APP_ID` / `HOMELAB_BUMP_APP_KEY`. Template: `docs/release-bump.md` lines 120-135.
  - `ci.yml` calls the shared proof workflow with `runner: ["self-hosted","homelab-check"]`. `proof:full` needs Playwright chromium on `check01`.

## Research from the explorer (Notes-Archive, read-only, 2026-11-03)
- No `.github/`, no tags. `npm run package` (`scripts/package.mjs`) builds the tarball locally; version 0.1.0.
- `package.mjs` runs `npm ci --omit=dev --ignore-scripts`; sharp's prebuilt binary delivery under `--ignore-scripts` is unverified. Check the tarball on the target OS/arch before the first tag.
- Its comment says there are no production deps; sharp and tiptap are now production deps, so the comment is stale.
- `flow.yaml` `ship_override` (Rue, 2026-11-02): at the end of `build-notes-archive` push a new release tag. Coordinate: the tag is what makes the first Homelab deploy succeed.
- Migrations apply by filename only, forward-only, no checksum.
