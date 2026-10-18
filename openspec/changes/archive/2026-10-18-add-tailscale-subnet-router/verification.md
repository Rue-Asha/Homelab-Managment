verified-at: ca72423

## Layer 1: scripts/proof.sh --all (green, exit 0, 28 sensors, 0 non-PASS lines)

```
proof: 28 sensor(s), 0 failed
PASS: tailscale fixtures
PASS: check runner role has no deploy credentials
PASS: no Tailscale auth key in the repo
PASS: retired key path
proof: 28 sensor(s), 0 failed
```

Note: `.terraform` provider cache removed before the run; `.terraform.lock.hcl` drift restored, not staged. Round 2 (fixer commits c0a91a5, ca72423) re-verified from scratch.
Direct runs: `scripts/tests/tailscale.sh` and `scripts/tests/deploy-targets.sh` exit 0; `ok: Scenario:` lines below.

## Layer 2: coverage

| Scenario | proof | Evidence |
|---|---|---|
| tailscale01 is declared with the agreed identity | manual (diff review) | see checklist |
| Terraform sensors stay green with the new guest | unit | proof --all: "PASS: terraform validate", "PASS: Regression: arcade shares IP with check container" |
| An address or hostname collision fails the proof | unit | "PASS: unique-hosts fixtures"; fixture "duplicate ipv4 without vmids" in `scripts/tests/unique-hosts.sh:33` |
| The runner plan shows exactly one new container | manual (post-merge) | runbook step 2 |
| tailscale01 chains to proxmox_guest | manual (post-merge) | runbook step 3 |
| A merge never runs the operator playbook | unit | deploy-targets.sh: ok: Scenario: A merge never runs the operator playbook |
| A created tailscale01 gets no deploy | unit | deploy-targets.sh: ok: Scenario: A created tailscale01 gets no deploy |
| The first merge's deploy run shows the expected warning | manual (post-merge) | runbook step 2 |
| TUN passthrough runs before Tailscale | unit | tailscale.sh: ok: Scenario: TUN passthrough runs before Tailscale |
| The operator playbook targets only the tailscale group | unit | tailscale.sh: ok: Scenario: The operator playbook targets only the tailscale group |
| The TUN device exists after the first run | manual (post-merge) | runbook step 5 |
| A rerun on a host with TUN does not reboot it | manual (post-merge) | runbook step 6 |
| A recreated container gets the lines in its new config | manual (live rebuild) | Rebuild section |
| The repository URL names trixie when no release fact is known | unit | tailscale.sh: ok: Scenario: The repository URL names trixie when no release fact is known |
| Tailscale is installed and running on the guest | manual (post-merge) | runbook step 5 |
| Forwarding is on and survives a restart | manual (post-merge) | runbook step 5 |
| Forwarding that cannot be set fails the play | manual (R1, live) | diff review: no ignore_errors/failed_when false in configure.yml |
| A second run changes nothing | manual (post-merge) | runbook step 6 |
| Not logged in and no key fails before tailscale up | unit | tailscale.sh: ok: Scenario: Not logged in and no key fails before tailscale up |
| An unreadable backend state counts as not logged in | unit | tailscale.sh: ok: Scenario: An unreadable backend state counts as not logged in |
| First join advertises the route and tag | unit | tailscale.sh: ok: Scenario: First join advertises the route and tag |
| A logged-in node is not re-authenticated | unit | tailscale.sh: ok: Scenario: A logged-in node is not re-authenticated |
| A stopped node is brought back up without a key | unit | tailscale.sh: ok: Scenario: A stopped node is brought back up without a key |
| Changed advertise settings converge without re-auth | unit | tailscale.sh: ok: Scenario: Changed advertise settings converge without re-auth |
| A rejected key fails the play visibly | unit | tailscale.sh: ok: Scenario: A rejected key fails the play visibly |
| The router keeps Tailscale's default SNAT | unit | tailscale.sh: ok: Scenario: The router keeps Tailscale's default SNAT |
| The key is prompted hidden | unit | tailscale.sh: ok: Scenario: The key is prompted hidden |
| A committed auth key fails the proof | unit | sensor "PASS: no Tailscale auth key in the repo" (green, assignment check widened in c0a91a5); the red-once demonstration was not re-run by the verifier |
| The live join is approved without a click | manual (post-merge) | runbook steps 1, 5 |
| The policy snippet is in the docs | manual (doc review) | docs/tailscale-subnet-router.md "Tailnet policy" section (line 39) |
| A missing policy is the first troubleshooting line | manual (doc review) | Troubleshooting first bullet (line ~129) |
| Services answer from an off-LAN client | manual (post-merge) | runbook step 7 |
| The laptop reaches a guest from a foreign network | manual (post-merge) | runbook step 7 |
| A stopped router only cuts off-LAN access | manual (post-merge) | runbook step 8 |
| Pi-hole answers queries arriving from the router | manual (post-merge) | runbook step 7 |
| The checklist covers all three devices and the reason | manual (doc review) | Clients section |
| Phone at home with the router down is covered | manual (doc review) | "At home with the app on" paragraph |
| The laptop at home survives a stopped router | manual (post-merge) | runbook step 8 |
| No stale reference remains | manual (doc review) | rg line run: 6 hits, all generic `terraform -chdir` commands (terraform/README.md:33,102,103,111,112; README.md:72), none Tailscale-related |
| Rollout and rebuild flows are described | manual (doc review) | Roll out, Rerun, Rebuild sections |
| Other docs point to the operator playbook | manual (doc review) | README.md:21-22, terraform/README.md:144-158, docs/terraform-ansible-split.md:45,72-75,173 |
| The post-merge runbook lists every live step | manual (doc review) | runbook steps 1-8 |

Gaps: none.

## Manual checklist

- Diff review: `tailscale01` in hosts.auto.tfvars matches 192.168.0.230/24, group tailscale, tags vpn+terraform, 1 core/512 MiB/512 MiB swap/4 GiB, no vmid/features
- Doc review: policy snippet present; troubleshooting starts with "route awaiting approval"; clients checklist; runbook order
- Post-merge (live, on Rue's go), runbook in docs/tailscale-subnet-router.md: policy paste; merge, one create, approve infrastructure; CD warning logged; fetch-inventory + graph; tagged key; first run with on-box and console checks; second run changed=0 no reboot; phone/tablet URLs and dig @192.168.0.225; laptop ssh from foreign network; pct stop/start with laptop home on accept-routes=false
- Optional: show sensor "no Tailscale auth key in the repo" red with a throwaway staged key-shaped file

## Diffstat (origin/main...flow/add-tailscale-subnet-router)

 29 files changed, 1430 insertions(+), 89 deletions(-)

Screenshots: none

## Review

Round 1 (reviewer, `origin/main...flow/add-tailscale-subnet-router`, no blocking findings):

| Finding | Resolution |
|---|---|
| [weak] `scripts/tests/tailscale.sh:797` authkey assignment check missed quoted, flow-mapping and INI shapes | Fixed in `c0a91a5`. Old check printed `ok` for all three shapes, new one prints `FAIL`; `{tailscale_authkey: ""}` and the real tree stay ok. The check also skips `#` comment lines (the playbook's `-e tailscale_authkey=<key>` comment). |
| [spec] `join.yml` treats `NoState` and a failing `tailscale status --json` as not logged in, spec only said `NeedsLogin` | Fixed in `ca72423`. Spec requirement and design D2 now state it; new "Scenario: An unreadable backend state counts as not logged in" (red before, green after); the empty-key `fail_msg` now says `tailscaled` may be down or unreachable. |
| Unused `Restart tailscaled` handler (outside the categories) | Not changed: restored as it was, out of scope. |

Round 2 (reviewer, fresh context at `ca72423`): no findings. One soft spot, not a finding: the non-zero-exit sub-case of the new scenario does not grep for `NoState`, but the `fail_msg` always contains it.

Open for Gate 2: the added `fail_msg` sentence is shown for every empty-key failure, including a genuine `NeedsLogin`.
