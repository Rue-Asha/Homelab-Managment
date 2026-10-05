## 1. Declaration

- [x] 1.1 Re-add `pihole01` to `lxc_hosts` in `terraform/environments/homelab/hosts.auto.tfvars` with the block from `6be473d` and drop the "retired" trailing comment
- [x] 1.2 `git checkout 6cabf8e -- ansible/inventory/host_vars/pihole01/vault.yml` (only this file) (decrypt check left to Rue: the auto-mode classifier blocked `ansible-vault view`)

## 2. Docs

- [x] 2.1 Rewrite `docs/pihole.md` *Status*, *First-time apply* and *Rebuild from scratch* for the runner flow; add the runner01 `known_hosts` pre-check
- [x] 2.2 Correct the "pihole01 is currently not declared" paragraph in `terraform/README.md`

## 3. Proof

- [x] 3.1 `scripts/proof.sh --all` green
- [x] 3.2 Before merging: `ssh-keygen -F 192.168.0.225` on runner01's `known_hosts` finds nothing (Rue; last checked and cleaned 2026-10-05)
- [x] 3.3 Merge run: plan shows exactly one create, `apply` outputs `created=pihole01`, `pihole.yml` and its smoke check pass in the same run (manual)
- [x] 3.4 Second `pihole.yml` run shows `changed=0` and no FTL restart; `dig @192.168.0.225 example.org` answers (manual)
