## Why

`pihole01` was retired (`6be473d`) so the destroy path of the pipeline could be proven; the LAN has run on the router's fallback resolver since. `deploy-new-guests` (#20) made the deploy run `03_SERVICES` playbooks for guests the `apply` job just created, so the rebuild is now one merge — and it is the create proof the golden-template change left open.

## What Changes

- Re-add `pihole01` to `hosts.auto.tfvars` with the block removed in `6be473d` (vmid 225, `192.168.0.225/24`, group `pihole`, 1 core, 512 MiB RAM/swap, 4 GiB disk, tags `dns` and `terraform`).
- Bring back only `ansible/inventory/host_vars/pihole01/vault.yml` (from `6cabf8e`; encrypted with the `vault_pass` the runner holds). `bf4f8d9` (the generated `00-terraform.yml`) is not taken: the file is generated on the runner.
- Rewrite `docs/pihole.md` *Status*, *First-time apply* and *Rebuild from scratch* for the runner flow (merge → plan → `infrastructure` approval → apply → `pihole.yml` + smoke check), replacing the workstation `terraform apply` / `fetch-inventory.sh` / `bootstrap.yml` steps.
- Pre-merge check, already done: the stale `192.168.0.225` entry in runner01's `known_hosts` was removed (it would have failed the deploy with "host key changed"). The `apply` job pins the new key itself.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `pihole-dns`: the documentation requirement changes — `docs/pihole.md` describes the first apply and the rebuild as the runner flow, and its status line no longer says the guest is retired.

## Impact

- `terraform/environments/homelab/hosts.auto.tfvars`, `ansible/inventory/host_vars/pihole01/vault.yml`, `docs/pihole.md`; `terraform/README.md` if it still calls pihole01 removed.
- Merging creates LXC 225 and configures Pi-hole on it. DNS impact is nil while the router keeps its fallback resolver; pointing the router at `.225` stays a manual, optional step afterwards.
- Proof of the create path is the merge run itself: `apply` output `created` = `pihole01`, then `pihole.yml` with a green smoke check in the same workflow run. runner01 state was changed by hand (one `known_hosts` line).
