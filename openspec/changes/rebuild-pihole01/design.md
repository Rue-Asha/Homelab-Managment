## Context

`pihole01` (vmid 225, `.225`) was retired in `6be473d` to prove the destroy path. `deploy-new-guests` (#20) now passes the `apply` job's `created` set to `deploy-targets.sh`, so a merge that adds the guest also runs `pihole.yml`. The role, playbook and `host_vars/pihole01/vars.yml` are already on `main`; the router has its fallback resolver. This change only restores the declaration, the vault file and the docs.

## Goals / Non-Goals

**Goals:**
- One merge creates LXC 225 and ends with `pihole.yml` and its smoke check green in the same workflow run.
- `docs/pihole.md` describes that flow.

**Non-Goals:**
- Pointing the router at `.225` (manual, optional, after the checks).
- Changing the role, the playbook or the pinned version.
- Backing up Pi-hole state.

## Decisions

- **Take `6cabf8e` only, not `bf4f8d9`.** The vault file is encrypted with the `vault_pass` the runner already holds (Rue confirmed). `00-terraform.yml` is generated and gitignored-by-contract; committing it would fight the generator.
- **Delete the stale `known_hosts` line instead of changing the pinning.** The `apply` job never overwrites an existing key, by design (a changed key must fail a deploy). The only stale entry was one-off; it was removed by hand on runner01 before this change (`ssh-keygen -R`, original kept as `known_hosts.old`).
- **Same sizing as the spec** (1 core, 512/512 MiB, 4 GiB), not the golden template's defaults, because the spec's first requirement fixes it.

## Risks / Trade-offs

- [First live create through the pipeline; any failure leaves a half-created guest] → the `apply` is approval-gated and a failed deploy is re-run, not rolled back; `terraform destroy -target` for the one guest is the reset.
- [FTL or Pi-hole install fails on Debian 13 / unprivileged LXC] → known fallbacks are listed in `docs/pihole.md` *Watch on the first run*; the router fallback keeps DNS up meanwhile.
- [A key for `.225` reappears on runner01 before merge] → re-run the pre-check immediately before merging.
- [`created` is empty because the guest already exists] → the deploy then maps only the diff, which skips pihole; verify the plan shows one create.
