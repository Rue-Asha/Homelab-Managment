## Context

The repo is two peer layers, `ansible/` and `terraform/`, and every command runs
from the repo root (`.envrc` sets `ANSIBLE_CONFIG`). `CLAUDE.md` lists the
pre-commit checks and says never to apply Terraform or run a playbook against
real hosts without asking. Neither rule is enforced.

`.claude/hooks/iac-proof-gate.sh` (commit `c7a0bf9`) was a first gate, but:

- no `settings.json` registers it, so it never runs;
- it ignores the hook's stdin JSON, so once registered on `Bash` it would run on
  every command, not just `git commit`;
- `terraform validate` / `tflint` run in the repo root, which has no `.tf` files
  since the layer split;
- logs go to fixed `/tmp/*.log` paths.

The global `~/.claude/hooks/safety-check.sh` shows the input-parsing pattern
already in use: `jq -r '.tool_input.command'`, block with exit 2.

## Goals / Non-Goals

**Goals:**
- One sensor runner shared by the commit gate, the `/proof` verb, and humans.
- A commit gate that blocks the agent with actionable `INVARIANT_VIOLATION` output.
- A human confirmation on every agent command that changes real hosts.
- Everything checked in; nothing per-machine.

**Non-Goals:**
- Deploy-time sensors (post-playbook `systemctl is-active` / HTTP checks) — the
  natural next change, built on this runner.
- Read-only production access for the agent (Proxmox `PVEAuditor` token,
  journal-only SSH user).
- `checkov` / `trivy` — not installed; add as a sensor once they are.
- A native git `pre-commit` hook for human commits (see Open Questions).
- Treating the gates as a security boundary against a hostile agent. They
  catch honest mistakes; a determined `bash -c` wrapper gets around them.

## Decisions

### One runner, thin hooks

`scripts/proof.sh` holds all sensor logic. `iac-proof-gate.sh` only parses the
hook input, decides whether the command is a commit, picks staged or full mode,
and calls the runner. `/proof` calls the same runner.

*Alternative:* sensors inside the hook (as today). Rejected — `/proof` and a
future git hook would duplicate them, and the hook could not be run by hand.

`scripts/` is a new top-level directory; the runner is repo tooling, not
Claude-specific, so it does not belong under `.claude/`.

### Sensor scoping

| Changed path | Sensors | Violation code |
|---|---|---|
| `*.tfstate`, `*.tfstate.*` | — (always fails) | `TFSTATE_STAGED` |
| `terraform/**` | `terraform fmt -check -recursive terraform/` | `TERRAFORM_FMT_FAILED` |
| | `terraform -chdir=terraform/environments/homelab validate` | `TERRAFORM_VALIDATE_FAILED` |
| | `tflint --chdir=terraform/environments/homelab` | `TFLINT_FAILED` |
| `ansible/**/*.yml` | `ansible-lint <files>` from the root | `ANSIBLE_LINT_FAILED` |
| `ansible/playbooks/**/*.yml` | `ansible-playbook --syntax-check <playbook>` | `ANSIBLE_SYNTAX_CHECK_FAILED` |

All sensors run even after one fails, so the agent gets every violation in one
round. Tool output is captured in a `mktemp` file and removed on exit.
`terraform validate` needs an initialised working dir: if `.terraform/` is
missing the runner runs `terraform init -backend=false -input=false` first
(failing as `TERRAFORM_INIT_FAILED`). That fetches providers from the registry
but never touches the Proxmox node.

Missing binaries fail as `SENSOR_UNAVAILABLE (<tool>)` — a skipped sensor that
reports success is the false "done" the harness exists to prevent.

### Commit detection and staged vs full mode

The gate reads `.tool_input.command` and matches `git` followed by optional
global flags (`-C <dir>`, `-c <k=v>`) then `commit`, anywhere after a command
separator (`^`, `;`, `&&`, `||`, `|`). If the same command also contains
`git add` or a `commit` flag with `-a`/`--all`, it uses full mode, because
`PreToolUse` runs before the add and the index is still stale.

### Host-action gate returns `ask`, not a block

`iac-apply-gate.sh` emits
`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"…"}}`
for `terraform … apply|destroy` (any `-chdir=` placement) and `ansible-playbook`
without `--check`/`-C`/`--syntax-check`. The rule in `CLAUDE.md` is "ask
first", not "never", and `ask` overrides auto mode.

*Alternative:* `permissions.ask` rules in `settings.json`. Rejected — they
prefix-match, so `Bash(terraform apply:*)` misses `terraform -chdir=… apply`,
and there is no way to say "ansible-playbook *without* `--check`".

*Bigger alternative, deferred:* a proof-based apply gate that only allows
`apply` when a saved plan file exists that is newer than every `.tf` change, and
applies that plan. That turns a human click into evidence, but it changes how
applies are run. Worth doing once the `ask` gate has been lived with.

### Two hook scripts, not a dispatcher

Each script exits 0 immediately on a non-matching command. Two small files with
one job each match the per-function task-file habit in the roles; a single
dispatcher saves one `jq` call per Bash command, which is negligible.

## Risks / Trade-offs

- [Regex matching misses indirect invocations (`bash -c`, a Makefile)] →
  accepted; documented as a non-goal. The gates target the agent's normal path.
- [`ansible-lint` on single files can report differently from a whole-repo run]
  → full mode lints everything; `/proof --all` before a PR.
- [A slow sensor run on every agent commit] → staged mode keeps it to the
  layers that changed; Terraform sensors only run when `terraform/` changed.
- [`terraform init` in the sensor needs network on a fresh clone] → only when
  `.terraform/` is missing; failure surfaces as `TERRAFORM_VALIDATE_FAILED` with
  the init output.
- [False positive on `ansible-playbook` mentioned in an argument, e.g. a commit
  message] → the result is a prompt, not a block, so the cost is one click.

## Migration Plan

Additive. Merging the change activates the gates for anyone opening the repo in
Claude Code. Rollback: remove the `hooks` entries from `.claude/settings.json`.

## Open Questions

- Should humans get the same gate as a native git `pre-commit` hook calling
  `scripts/proof.sh --staged`? Commit `c7a0bf9`'s message suggests that was
  the original intent; it is a one-line follow-up once the runner exists.
