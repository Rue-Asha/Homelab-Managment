verified-at: a495f13

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
`openspec validate add-pihole --strict`: Change 'add-pihole' is valid.

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
- Rue: first real run output shows no password; `no_log` present on the password-handling tasks in the diff (the variables assert intentionally has none).
- Rue: confirm spike S9 install shape on the first apply.
- Rue: fresh host gets the pinned `pihole_version` (real run); first real run, check `packages.yml` "Check that the pinned core tag exists upstream" runs after git is installed and is skipped once the pin is installed.
- Rue: deliberately bad pin fails the play at the `git ls-remote` tag check, before the installer runs, and leaves the installed version (real host).
- Rue: DNS keeps answering during the re-run, no FTL restart in the second run.
- Rue: on a host with pihole-FTL stopped, a real run starts FTL (service.yml now runs before configure.yml) and the login probe then passes.
- Rue: `http://192.168.0.225/admin` accepts the vault password (needs vault file).
- Rue: unchanged password not re-applied (second run `changed=0`).
- Rue: `--check` against `pihole01` without the vault file fails the play, and the failing message names `pihole_password` and `host_vars/pihole01/vault.yml` (not "censored").
- Rue: stop FTL (or point `pihole_smoke_url` at a dead port) and confirm the play fails with the "Web: ... answered ..." message after retries; on a healthy host confirm `verify.yml` web check passes on 200/30x (it retries on a status check, not task failure).
- Rue: review `tasks/verify.yml` diff, smoke check needs no vault.
- Rue: review diff, no firewall/runtime install in the pihole role, no `github_runner` target.
- Rue: read `docs/pihole.md` for first apply, bump, recovery; outage risk and router fallback; read `terraform/README.md` to confirm pihole01 is no longer described as removed.
- Rue, tasks 8.1-8.5 (intentionally unchecked rollout): 8.1 create vault.yml; 8.2 terraform plan/apply and commit regenerated `00-terraform.yml`; 8.3 bootstrap.yml, pihole.yml --check, real run, rerun expecting changed=0; 8.4 dig blocked/resolves plus admin login from LAN; 8.5 bump `pihole_version` via PR and merge.

## Diffstat (main...flow/add-pihole)

27 files changed, 1078 insertions(+), 12 deletions(-) (excluding this file)

## Screenshots

none

## Review

Three rounds (fresh-context reviewer each time, static read only). Nothing in the role could be run against a real host, so role behaviour is evidenced by ansible-lint, syntax-check and review, not by execution.

### Round 1 — fixed in c4c59f1
- [spec] `tasks/verify.yml`: the web half of the smoke check could never fail the play (`failed_when: false` plus `is succeeded`). Fixed: `pihole_smoke_web_ok` tests the status (200 or 30x), retries on it, and the failure message names the check. A throwaway localhost check of the status logic passed for 200/302 and failed for 404, -1, 503 and a missing status; the retry loop itself was read, not run.
- [spec] `git ls-remote` ran in `prepare.yml` before `git` was installed. `common` does install `git` by default, but the role then depended on it. Fixed: the tag check moved to the end of `packages.yml`; the input asserts stay first in `prepare.yml`.

### Round 2 — fixed in 5c9ac59, a66b47c
- [bug] `tasks/prepare.yml`: `no_log: true` on the variables assert censored its `fail_msg`, so a missing `pihole_password` showed "censored" instead of naming the variable and `host_vars/pihole01/vault.yml`. Fixed: `no_log` removed (conditions only test `is defined` and `length`); the tasks in `configure.yml` that handle the password keep `no_log`.
- [mismatch] The spec listed `docs/tailscale-subnet-router.md` as carrying a stale "removed" mention. It only shows pihole01 as a host behind the router and was already accurate. Fixed in the artifacts: proposal, delta spec and tasks.md now name `terraform/README.md`.
- Accepted, not changed: the web check accepts 200 and 301/302/303/307/308 (broader than the spec); `verify.yml` asserts the installed core version equals the pin and logs component versions (no scenario, covered by design.md).

### Round 3 — open at the cap
- [correctness] `tasks/configure.yml` (login probe) runs before `tasks/service.yml`: `POST /api/auth` is retried 10 times at 3 s whenever the `pihole-FTL` binary exists, before `service.yml` has started FTL. Failing input: Pi-hole installed but `pihole-FTL` stopped or crashed (for example after a reboot with the unit disabled). The play fails after about 30 s and never starts FTL, so the role cannot recover a stopped service. Fix: run `service.yml` before `configure.yml`, or guard the probe on the service state. Not fixed: round cap reached; Gate 2 decides.
- [mismatch] "listening on eth0 for the LAN only": only `dns.interface` is set; `dns.listeningMode` is left at the Pi-hole default, so "LAN only" rests on that default. Both related scenarios are manual. Not fixed.
- [minor] Under `--check` on an installed host the settings and `setpassword` commands are skipped, so `--check` does not show drift in those two. Matches the spec wording. Not fixed.
- [minor] `pihole setpassword <pw>` passes the password in argv, visible in `ps` on the host while it runs; `no_log` only hides it from Ansible output. Accepted for now, Rue decides at Gate 2.
- Note: the "A terraform-only diff deploys nothing" fixture changes `terraform/main.tf` rather than `hosts.auto.tfvars`; the behaviour it pins is the same. The `unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE` line in `scripts/tests/deploy-targets.sh` is a harness fix with no scenario. The two widened fixture expectations ("deleted playbook is skipped", "common runs its services…") are justified by the new pihole play that uses `common`.
