## MODIFIED Requirements

### Requirement: Pi-hole is documented, including the DNS-outage risk

`docs/pihole.md` SHALL describe what it is, how to create it and rebuild it through the runner flow (merge, plan, `infrastructure` approval, apply, `pihole.yml` with its smoke check), how to bump the version and how to recover. Its status line SHALL NOT call `pihole01` retired or undeclared. It SHALL state the DNS-outage risk and the router-fallback step even though that step is a Non-Goal of the automation, and the pre-merge check that runner01's `known_hosts` holds no entry for `192.168.0.225`. `terraform/README.md` SHALL no longer describe pihole01 as removed or gone; `docs/tailscale-subnet-router.md` only shows pihole01 as a host behind the router and needs no change.

#### Scenario: The doc covers the runner flow, bump and recovery
- **WHEN** `docs/pihole.md` is read
- **THEN** it describes creation and rebuild as the runner flow with no workstation `terraform apply`, `fetch-inventory.sh` or `bootstrap.yml` step, plus the version-bump PR and the recovery path
- **proof:** manual (prose; no sensor)

#### Scenario: The outage risk and router fallback are stated
- **WHEN** `docs/pihole.md` is read
- **THEN** it states that the LAN loses DNS if the router points at .225 and the box is down, and names the router fallback-resolver step as manual
- **proof:** manual (prose; no sensor)

#### Scenario: The known_hosts pre-check is stated
- **WHEN** `docs/pihole.md` is read
- **THEN** it says to check `ssh-keygen -F 192.168.0.225` on runner01 before merging a rebuild and to remove a stale entry
- **proof:** manual (prose; no sensor)

#### Scenario: Stale "removed" mentions are corrected
- **WHEN** `terraform/README.md` and the status line of `docs/pihole.md` are read
- **THEN** pihole01 is described as present again (one paragraph of correction, not a rewrite)
- **proof:** manual (prose; no sensor)
