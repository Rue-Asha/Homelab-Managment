Waves: Wave 1: U1, U2 (disjoint files, shared interface fixed in design.md `## Contracts`). No ⚠ irreversible task: nothing here applies Terraform or runs a playbook; the merge deploy happens in Ship.

## 1. Created guests in deploy-targets.sh, with fixtures
> unit: depends=none · scope=S2,S3 · files=scripts/deploy-targets.sh, scripts/tests/deploy-targets.sh
- [x] 1.1 Extend the synthetic inventory in `scripts/tests/deploy-targets.sh` with a bare guest (e.g. `bare01` directly under `proxmox_guest`, targeted by no playbook) and confirm every existing fixture still passes unchanged
- [x] 1.2 Write the fixtures from the THEN clauses of every scenario under "A created guest selects its service playbooks", named `Scenario: <title>`, before the code; assert stdout, stderr and exit status where the scenario names them (the current `expect` merges stderr into the output, so add a helper that keeps them apart)
- [x] 1.3 Implement `--created "<host> ..."` in `scripts/deploy-targets.sh` per `## Contracts`: option parsing (diff form only, else exit 64), inventory check with exit 1 in every diff path including the run-everything shortcuts, union with the diff selection, sorted unique output, stderr note for hosts without a service playbook; update the usage comment at the top
- [x] 1.4 Run `scripts/tests/deploy-targets.sh` and `scripts/proof.sh --all`; both green, one `ok:` per created-guest scenario

## 2. Hand created guests from apply to deploy, and document it
> unit: depends=none · scope=S1,S4 · files=scripts/tf-ci.sh, .github/workflows/deploy.yml, docs/deploy-runner.md
- [x] 2.1 `scripts/tf-ci.sh apply`: after the host-key loop, append `created=<space-separated names>` (empty when none) to `$GITHUB_OUTPUT`, required like `GITHUB_SHA`; update the header comment; print nothing new to the public log beyond host names
- [x] 2.2 `.github/workflows/deploy.yml`: `id: apply` on the Apply step, `outputs.created` on the `apply` job, `CREATED: ${{ needs.apply.outputs.created }}` on the Select playbooks step, `--created "$CREATED"` in the push branch only; dispatch branch and the `deploy` job's `needs`/`if` unchanged; adjust the header comment
- [x] 2.3 `docs/deploy-runner.md`: intro paragraph and Day 2 "A guest was added by the pipeline" say the guest's `03_SERVICES` playbooks run in the same run, a bare guest gets none, a recreated guest still needs `deploy_runner.yml`
- [x] 2.4 `bash -n scripts/tf-ci.sh`, `shellcheck scripts/tf-ci.sh` if installed, then `scripts/proof.sh --all` (covers the workflow-trigger check); the wiring itself is proven live (scenario proof lines: this change's merge run and `rebuild-pihole01`)
