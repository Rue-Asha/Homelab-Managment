## Context

`ci.yml` runs `scripts/proof.sh --all` on `ubuntu-24.04` and installs every
tool per job. `runner01` is the only self-hosted runner; it holds the deploy
credentials and `workflow-triggers.py` keeps it away from PR events by banning
`self-hosted` under any untrusted trigger. A second runner for checks needs the
opposite property (it must take PR events) without weakening the first.

The `github_runner` role and `egress_firewall` role already do most of the
work: unprivileged user, pinned runner release, systemd unit, nftables egress
policy. Not reusable as-is: `github_runner` also installs Terraform, the
deploy credentials and a deploy-flavoured `.env`.

## Goals / Non-Goals

**Goals:**
- `proof` runs on a homelab runner that holds nothing and reaches nothing.
- `runner01` stays unreachable from PR code, and the proof still enforces it.
- Tool versions stay pinned in one place per tool.

**Non-Goals:**
- Ephemeral runners, a VLAN, moving `security-baseline`, or any change to the
  deploy workflow (see proposal).

## Decisions

**D1: New role `check_runner`, not a flag on `github_runner`.** The two share
only "install and register an Actions runner". A flag would put `if deploy`
around credentials, Terraform and the vault file, and a mistake there leaks
deploy credentials onto the PR-facing box. The duplicated install/register
tasks are about 40 lines. *Alternative:* extract a `github_runner_core`
role; it buys no duplication but touches the deploy runner, which this change
promises not to. Do it later if a third runner appears.

**D2: Persistent runner, workspace wiped per job.** Ephemeral needs a fresh
registration token per job, which means a PAT or GitHub App key on `check01`:
a secret on the PR-facing box, the thing the isolation is meant to avoid.
Persistent costs: a malicious PR step can leave state that affects later
jobs, e.g. a poisoned `~/.cache` or pip site-packages. Mitigations: no sudo,
`NoNewPrivileges`, tools in root-owned locations (`/usr/local`, a root-owned
venv), `_work` wiped by a workflow step, and nothing on the box worth taking.
Worst case is a wrong green `proof`, and Rue still reviews the PR.
*What the bigger design would buy:* a clean box per job, so poisoning cannot
persist. It could be built with systemd + `--ephemeral` + JIT config from a
GitHub App key held outside the box, or with an LXC snapshot rollback driven
from `runner01`. Both add a secret or a cross-runner trust path.

**D3: Isolation by host firewall, not VLAN.** Reuse `egress_firewall` with
`egress_firewall_ssh_targets: []` and `egress_firewall_api_targets: []`.
Result: DNS and TCP 80/443 to non-private addresses only. LAN, guests,
`proxmox1` and `runner01` are unreachable outbound. The runner has no sudo,
so a job cannot flush the rules. *Gap:* inbound is not restricted by this role;
a LAN host could connect to `check01`. It runs no service listening beyond sshd,
and sshd stays key-only for the `ansible` user. *Bigger design:* a separate
bridge/VLAN, also stopping `check01` from being a foothold into the LAN.

**D4: DNS stays LAN-resolved.** The firewall allows port 53 to anywhere;
guests resolve via the LAN resolver. Left as is; narrowing DNS to the resolver
is a change to `egress_firewall` that affects `runner01`.

**D5: Toolchain baked by Ansible, pinned once.** Terraform and tflint versions
are already pinned in `ci.yml`; ansible-core, ansible-lint and checkov in
`ci/requirements.txt`. The role reads `ci/requirements.txt` like
`github_runner` does and takes Terraform/tflint versions as role defaults with
a comment tying them to `ci.yml`. Keeping `setup-terraform`/`setup-tflint`
steps in `ci.yml` is not possible on a no-sudo runner without a hosted tool
cache, so the steps are removed and the pins live in the role. Drift between the
two copies of the Terraform pin is a risk, see below.

**D6: Trigger rule becomes an allow-list.** For a job whose workflow has an
untrusted trigger: flag the job unless its labels contain no self-hosted
indicator, or are exactly `self-hosted` plus `homelab-check`. Labels are
compared as plain strings; expressions (`${{`) still fail. Any job carrying
`homelab-deploy` fails regardless. This keeps the existing guarantee for
`runner01` and permits exactly one new case. A matrix or `runs-on:` group
object is treated like a list of its labels as today.
*Known limit:* the check runs from the PR's own checkout, so a PR that edits
the check defeats it. It guards against mistakes. The real boundary is who can
open a PR (solo repo, fork approval for all outside contributors).

**D7: Fallback is a one-line revert.** If `check01` is down, the required
`proof` check stays pending. Documented fix: change `runs-on` back to
`ubuntu-24.04` and re-add the setup steps (they are in git history). Not
automated; a `vars`-driven runner choice would put an expression into
`runs-on`, which D6 rejects.

**D8: `check01` is not plan-protected.** `plan-protected.sh` exists because
`runner01` applies Terraform and holds state. Losing `check01` blocks merges
but breaks nothing; the D7 fallback covers it.

## Contracts

- Label: `homelab-check`. Deploy label stays `homelab-deploy`.
- Group: `check_runner`. Host: `check01`, vmid 226, `192.168.0.226/24`.
- Test: `scripts/tests/workflow-triggers.sh`, run by `proof.sh` when
  `scripts/checks/workflow-triggers.py` or the test changes.

## Risks / Trade-offs

- [Poisoned persistent runner gives a wrong green check] → no secrets, no
  sudo, root-owned tools, wiped workspace, PR review; ephemeral is the upgrade.
- [Terraform/tflint pinned in both `ci.yml`-history and the role] → one pin in
  the role, with a comment; `docs/check-runner.md` lists where to bump.
- [`check01` down blocks every merge] → D7 fallback documented.
- [Relaxed trigger rule is a security regression if wrong] → fixture tests
  cover deploy label, mixed labels, expressions, no-label, and trusted triggers.
- [Inbound to `check01` unrestricted] → D3, accepted for v1.
- [Egress allows any public host on 443] → same as `runner01`; a malicious
  PR can exfiltrate only what is in the repo, which is public or already
  readable by the PR author.

## Migration Plan

1. Merge the change with `ci.yml` still on `ubuntu-24.04` (declare host, role,
   docs, trigger rule, tests). The deploy workflow plans and applies `check01`
   after approval.
2. Run the base bootstrap play against `check01`, then the check-runner play with
   a registration token; verify the boundary checks in `docs/check-runner.md`.
3. Second PR flips `ci.yml` `proof` to `homelab-check`. It must pass on `check01`
   before merging.
4. Rollback: revert that PR's `runs-on` line.

## Open Questions

- Is `Rue-Asha/Homelab-Managment` public? If yes, confirm the fork-PR approval
  setting before step 3.
- Does the router/DNS plan have room for `.226`?
