## Context

`deploy.yml` runs `plan` → `apply` (after `infrastructure` approval) → `deploy` on `runner01`.
`scripts/tf-ci.sh apply` already computes the guests the plan creates
(`.change.actions == ["create"]` on `module.lxc["<name>"]...container.this`) to pin their host
keys, then drops that list. `deploy` renders the inventory from state and calls
`scripts/deploy-targets.sh <before> <after>`, which maps only the `ansible/` diff to playbooks.
So a tfvars-only merge creates a guest that nothing configures.

## Goals / Non-Goals

Goals: S1–S4 of `scope.md`. Non-goals as in `proposal.md` (no automatic re-pin of recreated
guests, no bootstrap run, no `pihole` dispatch option, no `pihole01` rebuild here).

## Decisions

- **Source of "new guest" is the apply result, not a `hosts.auto.tfvars` diff.** It reflects what
  was actually created and reuses the set the host-key pinning already computes (Rue, explore).
- **Two PRs:** this change first, the `pihole01` rebuild as its own change afterwards, so a failed
  live create is clearly not this fix's merge, and the rebuild is a clean create proof (Rue, explore).
- **Space-separated string across jobs** (R3): GitHub job outputs are strings; host names are
  `[a-z0-9-]`, so a space-separated list needs no encoding.
- **Created guests only extend the diff mode.** `workflow_dispatch` keeps its `all` / named-playbook
  behaviour unchanged (scope flow "Unchanged"), so the workflow passes `--created` only on `push`.
  `all` already covers every playbook; a named playbook stays exactly that playbook.
- **Unknown created host fails** instead of being skipped: a name `apply` created that the freshly
  rendered inventory lacks means render and state disagree, and a silent skip would leave the guest
  empty again — the bug this change fixes.
- **A created guest without a service playbook is logged, not an error** (bare guests are legitimate;
  `github_runner` guests are never in a `03_SERVICES` playbook by the existing rule).

## Contracts

Shared by U1 (`deploy-targets.sh` + fixtures) and U2 (`tf-ci.sh`, `deploy.yml`, docs). Fixed here
so both units run in parallel.

**`tf-ci.sh apply` → `$GITHUB_OUTPUT`**
- After the host-key loop succeeds, `tf-ci.sh apply` appends exactly one line
  `created=<names>` to `"$GITHUB_OUTPUT"`. `<names>` is the existing `created` array joined by
  single spaces, in plan-JSON order. No guest created → `created=` (empty value).
- `GITHUB_OUTPUT` is required like `GITHUB_SHA` (`: "${GITHUB_OUTPUT:?}"`); the script only runs in Actions.
- The pinning loop, its `exit 1` on a missing key, and the public-log rule (no plan/state values
  printed) are unchanged.

**`deploy.yml`**
- `apply` job: the Apply step gets `id: apply`; the job declares
  `outputs: created: ${{ steps.apply.outputs.created }}`.
- `deploy` job, Select playbooks step: `env: CREATED: ${{ needs.apply.outputs.created }}`.
  When `apply` was skipped this is the empty string.
- `push`: `args=(--created "$CREATED" "$BEFORE" "$AFTER")`. `workflow_dispatch`: unchanged.
- The `deploy` job's `needs`/`if` stay as they are (failed or rejected apply → no deploy).

**`scripts/deploy-targets.sh` input**
- Usage: `scripts/deploy-targets.sh [--created "<host> ..."] <before> <after> | --all | <playbook>`.
  `--created` is accepted only in front of `<before> <after>`; with `--all` or a name it is a usage
  error (exit 64).
- The value is a whitespace-separated list of inventory host names; it may be empty. Empty (or
  the option absent) → output identical to today for the same diff.
- Every created host must be a host in `ansible-inventory --list` of the working tree; otherwise
  print `deploy-targets: created host not in inventory: <host>` to stderr and exit 1, with no
  playbook on stdout. This check runs in every path of the diff form, including the
  "run everything" shortcuts.
- A created host selects every `03_SERVICES` playbook whose `--list-hosts` contains it (same as a
  `host_vars/<host>/` change). Selection is the union with the diff's selection.
- stdout: unchanged format — one playbook path per line, each at most once, sorted by path.
- stderr: for each created host that no `03_SERVICES` playbook targets,
  `deploy-targets: <host> has no 03_SERVICES playbook` (informational, exit status 0).

## Risks / Trade-offs

- R1 The create path with an API-token-only runner has never run → accepted: the split-off
  `rebuild-pihole01` is the first live create and proves it.
- R2 A stale `.225` key in runner01's `known_hosts` would fail the rebuild's deploy → accepted:
  checked in `rebuild-pihole01` before merging.
- R3 Job outputs are strings → resolved: space-separated list (Contracts).
- The workflow wiring and `tf-ci.sh` cannot run locally (they need the runner, state and the PVE
  token); their scenarios are proven by this change's own merge run and by `rebuild-pihole01`.

## Migration Plan

None. Merging this change touches no `terraform/`, so `apply` is skipped, `created` is empty and
the deploy selects exactly what it would have before (Done criterion 2).
