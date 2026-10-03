## 1. Sensor runner

- [x] 1.1 Create `scripts/proof.sh` with `--staged` (default) and `--all` modes that collect the changed-file list from the index or `git ls-files`
- [x] 1.2 Add the `TFSTATE_STAGED` sensor
- [x] 1.3 Add the Terraform sensors (`fmt -check -recursive`, `validate` with `init -backend=false` when `.terraform/` is missing, `tflint`) against `terraform/environments/homelab`, run only when `terraform/` changed
- [x] 1.4 Add the Ansible sensors (`ansible-lint` on changed `ansible/**/*.yml`, `--syntax-check` on changed playbooks), run from the repo root
- [x] 1.5 Report `SENSOR_UNAVAILABLE (<tool>)` for missing binaries; run every sensor before exiting; keep tool output in a `mktemp` file removed on exit
- [x] 1.6 Verify by hand: clean tree exits 0; a deliberately unformatted `.tf`, a lint-failing role file, a broken playbook, and a force-added `.tfstate` each produce their violation code and a non-zero exit (revert the fixtures afterwards)

## 2. Commit gate

- [x] 2.1 Rewrite `.claude/hooks/iac-proof-gate.sh` to read `.tool_input.command` from stdin and exit 0 unless the command runs `git commit` (including `git -C <dir> commit` and after `;`/`&&`/`||`)
- [x] 2.2 Choose full mode when the command also runs `git add` or `commit -a`/`--all`; otherwise staged mode; call `scripts/proof.sh` and exit 2 with its output on stderr when it fails
- [x] 2.3 Verify by piping sample hook JSON: `rg foo` → exit 0 with no sensor run; `git commit -m x` with a failing staged file → exit 2 with violations; `git add … && git commit …` → full mode

## 3. Host-action gate

- [x] 3.1 Create `.claude/hooks/iac-apply-gate.sh` that emits a `permissionDecision: "ask"` JSON with a reason for `terraform … apply|destroy` (any `-chdir=` placement) and `ansible-playbook` without `--check`/`-C`/`--syntax-check`
- [x] 3.2 Verify by piping sample hook JSON: `terraform -chdir=terraform/environments/homelab apply` and a bare `ansible-playbook …/pihole.yml` → `ask`; `terraform plan`, `ansible-playbook … --check --diff` → exit 0 with no output

## 4. Wiring and verb

- [x] 4.1 Add a checked-in `.claude/settings.json` registering both scripts as `PreToolUse` hooks with matcher `Bash`, using `$CLAUDE_PROJECT_DIR` paths
- [x] 4.2 Add `.claude/commands/proof.md`: runs `scripts/proof.sh` (`--all` when the argument says so) and reports one pass/fail line per sensor, followed by details of any failure
- [x] 4.3 Verify live in a new Claude Code session: a no-op Bash command is unaffected, `terraform plan` runs unprompted, `terraform apply` prompts (decline it), `/proof` reports per-sensor results

## 5. Docs and checks

- [x] 5.1 Update `CLAUDE.md` "Before committing" to name `scripts/proof.sh` / `/proof` as the way to run the checks, and mention the host-action gate under the Terraform/Ansible rules
- [x] 5.2 Add a short harness section to `README.md`
- [x] 5.3 Run `shellcheck` on the three scripts if available, then `scripts/proof.sh --all` on the whole repo, and fix anything it reports
