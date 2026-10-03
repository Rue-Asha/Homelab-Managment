## Why

The rules that matter most in this repo — lint before committing, never
`terraform apply` or run a playbook against real hosts without asking — exist
only as prose in `CLAUDE.md`, which the agent follows most of the time but not
by construction. The one attempt at enforcement, `.claude/hooks/iac-proof-gate.sh`,
is not wired into any `settings.json`, does not read the hook input (so it
cannot tell `git commit` from `ls`), and still validates Terraform from the
repo root, which the `ansible/` + `terraform/` split has made wrong.

Following the minimum-viable-harness model (sensors, gates, backpressure), this
change turns those prose policies into a gate that demands proof before the
agent may proceed.

## What Changes

- Add a single sensor runner, `scripts/proof.sh`, that runs the "Before
  committing" checks from `CLAUDE.md` scoped to the changed files, and reports
  each failure as an `INVARIANT_VIOLATION: <CODE>` line. It is the shared
  evidence source for the gate and for humans.
- Add a staged-state sensor: a commit that stages any `*.tfstate` file fails
  even when `.gitignore` was bypassed with `git add -f`.
- Rewrite `.claude/hooks/iac-proof-gate.sh` as a command-aware `PreToolUse`
  gate: it acts only on `git commit`, delegates to `scripts/proof.sh`, and
  blocks with exit 2 so the failures are fed back to the agent.
- Add `.claude/hooks/iac-apply-gate.sh`: `terraform apply`/`destroy` and any
  `ansible-playbook` run without `--check` or `--syntax-check` return a
  permission `ask`, so a human confirms every change to real hosts.
- Add a checked-in `.claude/settings.json` that wires both gates.
- Add a `/proof` slash command, the intent-level verb that runs the sensors on
  demand and summarises pass/fail per sensor.

## Capabilities

### New Capabilities
- `agent-harness`: proof sensors, the commit gate, the live-host action gate,
  and the `/proof` verb that govern what the coding agent may do in this repo.

### Modified Capabilities
<!-- none — terraform-provisioning and terraform-ansible-handoff describe the
     infrastructure, not how changes to it are gated -->

## Impact

- New: `scripts/proof.sh`, `.claude/hooks/iac-apply-gate.sh`,
  `.claude/settings.json`, `.claude/commands/proof.md`.
- Rewritten: `.claude/hooks/iac-proof-gate.sh`.
- Docs: `CLAUDE.md` "Before committing" points at `scripts/proof.sh`; README
  mentions the harness.
- Tooling: relies on `terraform`, `tflint`, `ansible-lint`, `ansible-playbook`,
  `jq`, all already installed. `checkov`/`trivy` are listed in `CLAUDE.md` but
  not installed; they are out of scope here.
- No change to any host, playbook, role, or Terraform resource.
