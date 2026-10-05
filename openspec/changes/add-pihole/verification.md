verified-at: c4c59f1

## Layer 1 — `scripts/proof.sh --all` (green)

```
PASS: syntax-check ansible/playbooks/03_SERVICES/life-manager.yml
PASS: syntax-check ansible/playbooks/03_SERVICES/pihole.yml
PASS: collection pins
PASS: workflow triggers
PASS: deploy-targets fixtures
proof: 12 sensor(s), 0 failed
```

Also PASS: terraform fmt, terraform validate, tflint, checkov, ansible-lint, syntax-check bootstrap.yml and deploy_runner.yml.
Fixtures (`bash scripts/tests/deploy-targets.sh`) print `ok: Scenario: <title>` for all five pihole scenarios.

## Layer 2 — spec coverage

| Scenario | proof | Evidence |
|---|---|---|
| Terraform shows exactly one new guest | manual (plan/apply need Proxmox API) | checklist |
| vmid and IP are declared independently | manual (diff review) | checklist |
| The host is added to the keyed map without count | manual (diff review) | checklist |
| Terraform sensors stay green | proof.sh | fmt, validate, tflint, checkov PASS |
| The role passes lint and syntax check | proof.sh | ansible-lint, syntax-check pihole.yml PASS |
| Re-running on an installed host changes nothing | manual | checklist |
| The installer is skipped when the pinned version is present | manual | checklist |
| The password never appears in output | manual | checklist |
| Spike S9 decides the install shape | manual | checklist |
| A fresh host gets the pinned version | manual | checklist |
| The pinned version is unavailable | manual | checklist |
| DNS keeps answering during a re-run | manual | checklist |
| Admin UI accepts the vault password | manual | checklist |
| An unchanged password is not re-applied | manual | checklist |
| Missing password fails the play | manual | checklist |
| The playbook has the agreed shape | proof.sh | syntax-check, ansible-lint PASS |
| A failing smoke check fails the play | manual | checklist |
| The smoke check runs without the vault | manual (diff review) | checklist |
| No host-level concern lives in the app role | manual (diff review) | checklist |
| Role change runs only the pihole playbook | fixture | `ok: Scenario: Role change runs only the pihole playbook` |
| Version bump runs only the pihole playbook | fixture | `ok: Scenario: Version bump runs only the pihole playbook` |
| Group vars of the pihole group run the pihole playbook | fixture | `ok: Scenario: Group vars of the pihole group run the pihole playbook` |
| A terraform-only diff deploys nothing | fixture | `ok: Scenario: A terraform-only diff deploys nothing` |
| A diff touching two services runs both | fixture | `ok: Scenario: A diff touching two services runs both` |
| Skips match the new role | proof.sh | ansible-lint PASS |
| The whole repo proof is green | proof.sh | 12 sensors, 0 failed |
| The doc covers first apply, bump and recovery | manual (prose) | checklist |
| The outage risk and router fallback are stated | manual (prose) | checklist |
| Stale "removed" mentions are corrected | manual (prose) | checklist |

Gaps: none.

## Manual checklist

- Rue: `terraform plan` shows exactly one new LXC (pihole01); needs Proxmox API.
- Rue: review `hosts.auto.tfvars` diff, vmid and IP are independent literals.
- Rue: review `terraform/` diff, host added to the keyed map, no `count`.
- Rue: second real `pihole.yml` run shows `changed=0` and the installer task skipped.
- Rue: first real run output shows no password; `no_log` present in diff.
- Rue: confirm spike S9 install shape on the first apply.
- Rue: fresh host gets the pinned `pihole_version` (real run); first real run, check `packages.yml` "Check that the pinned core tag exists upstream" runs after git is installed (moved from prepare.yml in c4c59f1) and is skipped once the pin is installed.
- Rue: deliberately bad pin fails the play at the `git ls-remote` tag check, before the installer runs, and leaves the installed version (real host).
- Rue: DNS keeps answering during the re-run, no FTL restart in the second run.
- Rue: `http://192.168.0.225/admin` accepts the vault password (needs vault file).
- Rue: unchanged password not re-applied (second run `changed=0`).
- Rue: `--check` against `pihole01` without the vault file fails the play.
- Rue: stop FTL (or point `pihole_smoke_url` at a dead port) and confirm the play fails with the "Web: ... answered ..." message after retries; on a healthy host confirm `verify.yml` web check passes on 200/30x (it now retries on a status check, not task failure, since c4c59f1).
- Rue: review `tasks/verify.yml` diff, smoke check needs no vault.
- Rue: review diff, no firewall/runtime install in the pihole role, no `github_runner` target.
- Rue: read `docs/pihole.md` for first apply, bump, recovery; outage risk and router fallback; stale "removed" mentions corrected.
- Rue, tasks 8.1-8.5 (intentionally unchecked rollout): 8.1 create vault.yml; 8.2 terraform plan/apply and commit regenerated `00-terraform.yml`; 8.3 bootstrap.yml, pihole.yml --check, real run, rerun expecting changed=0; 8.4 dig blocked/resolves plus admin login from LAN; 8.5 bump `pihole_version` via PR and merge.

## Diffstat (main...flow/add-pihole)

28 files changed, 1157 insertions(+), 12 deletions(-) (excluding this file)

## Screenshots

none
