## Context

`scripts/proof.sh` is already the single source of proof: the Claude Code
commit hook (`iac-proof-gate.sh`), `/proof`, and humans all call it. Only the
agent's commits are gated; Rue's own commits run nothing. It has a `--all` mode nobody automates. The
only Rue-Asha repo with Actions today is `Rue-Asha.github.io`, whose
`publish.yml` documents four publishing controls by hand. Both this repo and
Life-Manager are public, which rules out self-hosted runners for anything a fork
PR can trigger and makes every workflow a potential attack surface.

`ansible.cfg` points `vault_password_file` and `private_key_file` at paths under
`~/.config/homelab` and `~/.ssh` that do not exist on a runner. No vault-encrypted
file is tracked today.

## Goals / Non-Goals

**Goals:** an independent, enforced CI verdict for this repo; one shared
security baseline other repos adopt by SHA; checkov automated; one local commit
gate that Rue and the agent share.

**Non-Goals:** CD, Terraform plan/apply, Molecule — see proposal.

## Decisions

**CI calls `proof.sh --all`, nothing else.** The workflow installs tools and
runs the script; it owns no check list. Same pattern as `publish.yml` calling
`bin/check.ts`. *Alternative:* one workflow step per tool — readable in the
Actions UI, but a second definition of the check set that drifts from the hook.

**checkov becomes a proof sensor, not a CI-only step.** Keeps "CI = another
caller" true. Runs `checkov -d terraform/environments/homelab --framework
terraform --compact --quiet` when Terraform changed. Existing findings are fixed
or skipped inline as `#checkov:skip=<ID>:<reason>`, as CLAUDE.md already asks.

**CI enforces, a git hook gives feedback.** With CI as the merge authority, the
agent-only `PreToolUse` commit gate is no longer needed for correctness — but a
local gate still saves a push-and-wait round trip per mistake, and the agent
cannot see CI results without polling `gh`. So the gate stays, moved into git:
`.githooks/pre-commit` runs `scripts/proof.sh --staged`. The agent sees a
failing git hook in its Bash output just as it saw the Claude hook's exit 2,
and Rue's terminal/neovim commits get the same check. It is also more accurate:
git runs `pre-commit` after staging (with `GIT_INDEX_FILE` set for
`commit -a`), so the `--all` fallback for `git add && git commit` goes away.
*Alternative:* keep `iac-proof-gate.sh` — agent-only, and duplicates what the
git hook does.

**`core.hooksPath` is set from `.envrc`.** Git does not version hook
configuration, so `.envrc` runs `git config core.hooksPath .githooks` — idempotent,
and it lands in the shared repo config, so worktrees inherit it. A clone that
never ran `direnv allow` has no local gate; CI catches that.

**The agent may not bypass the hook.** `git commit --no-verify` / `-n` skips
`pre-commit` for anyone. A new `PreToolUse` hook,
`.claude/hooks/iac-no-verify-gate.sh`, blocks (exit 2) an agent `git commit`
carrying either flag. Permission `deny` rules match by command prefix and miss
the flag in other positions, hence a hook. Rue keeps `--no-verify` as a
deliberate escape hatch; CI still judges the result.

**Tool versions pinned in-repo.** Python tools (`ansible-core`, `ansible-lint`,
`checkov`) in `ci/requirements.txt` with exact versions; Terraform and tflint
through their setup actions with explicit versions; collections from
`ansible/collections/requirements.yml`. Local machines are not forced onto these
versions — the CI pin is the reference when they disagree.

**Runner-side config via environment, not by editing `ansible.cfg`.** The job
sets `ANSIBLE_VAULT_PASSWORD_FILE` to a throwaway file containing a dummy
string. Syntax-check and lint never open the private key, so
`private_key_file` needs nothing.

**Security baseline in its own public repo, `Rue-Asha/ci`.** Reusable
workflows from a public repo are callable by any repo without extra settings.
Its spec lives in this repo's `openspec/` because `Rue-Asha/ci` is too small to
carry its own planning; the code lives there. *Alternative:* the `.github`
special repo — it only provides workflow *templates* for organisations, not a
call target for a user account.

**Baseline tools run as pinned CLIs where possible.** actionlint, zizmor and
gitleaks are downloaded by version with a checksum check, instead of their
marketplace actions: fewer third-party actions with `GITHUB_TOKEN` access, and
`gitleaks-action` would need a licence key for org accounts.
Dependency review uses `actions/dependency-review-action` (first-party, needs
the PR's dependency graph).

**Dependabot over Renovate.** Native, no app installation, and it updates
SHA-pinned `uses:` lines including reusable-workflow refs, keeping the
`# vX.Y.Z` comment current — which requires `Rue-Asha/ci` to cut tags.
*Renovate would buy* grouped updates and a dashboard; not worth an app install
for three repos.

**Branch protection as a ruleset, set by hand.** Required checks: `proof` and
each baseline job by its exact name (e.g. `security-baseline / secret-scan`) —
rulesets match check names exactly, no wildcards, so the baseline's job names
are part of its interface and get fixed in the build. Admin bypass stays off so Rue's own pushes go through
PRs too — otherwise the "outside the harness" gap this change exists to close
reopens.

## Risks / Trade-offs

- [A vault-encrypted vars file is added later; syntax-check then fails to
  decrypt with the dummy password] → The dummy-password step is named for this;
  revisit it (e.g. skip decrypt-only checks) when the first vault file returns.
- [Local and CI tool versions disagree; green locally, red in CI] → Accepted —
  CI is authoritative. `ci/requirements.txt` gives a one-liner to match.
- [checkov flags existing Terraform; first CI run red] → Task group 1 runs it
  locally first and resolves findings before CI is wired.
- [Requiring PRs for Rue's own pushes slows hotfixes] → The bypass toggle is one
  click; that is a conscious, visible act, not a silent skip.
- [Agent bypasses the hook another way, e.g. `git -c core.hooksPath=… commit`]
  → Not gated locally; CI is the backstop and the commit is visible in review.
- [The git hook makes every commit slower, including WIP commits] → `--staged`
  runs only relevant sensors; Rue can `--no-verify` knowingly.
- [A compromised `Rue-Asha/ci` commit reaches every repo] → Callers pin by SHA,
  bumps arrive as reviewable PRs.

## Migration Plan

Additive except for the hook swap. Order: checkov sensor → git pre-commit hook
replaces `iac-proof-gate.sh` → `Rue-Asha/ci` → `ci.yml` → adopt baseline in
`Rue-Asha.github.io` → ruleset last, once both checks have been green on `main`.
Rollback: delete the ruleset; the workflows are inert without it. The hook swap
rolls back by restoring `iac-proof-gate.sh` in `.claude/settings.json`.

## Open Questions

- Should `proof.sh` print a `::error::` annotation per violation when
  `GITHUB_ACTIONS=true`? Nicer PR view, small change — decide during build.
