## Why

Every check in this repo runs only inside the agent harness: the commit gate
fires on agent commits, never on Rue's own commits, web edits, or bot PRs, and
the agent is grading its own work. A merge to `main` needs an independent,
enforced verdict from a clean environment — that is what CI adds. Locally, the
proof gate is wired only into Claude Code, so Rue's own commits get no fast
feedback either; one git hook can serve both. Checkov,
listed under "Before committing", has never run automatically at all.

The security controls `Rue-Asha.github.io/publish.yml` applies by hand (SHA
pinning, explicit permissions, no `pull_request_target`) are about to be needed
in three repos. Writing them once, centrally, is cheaper than keeping three
copies honest.

## What Changes

- New repo **`Rue-Asha/ci`** holding one reusable workflow,
  `security-baseline.yml` (`on: workflow_call`): workflow lint (actionlint +
  zizmor), secret scan (gitleaks), and dependency review on pull requests.
  Every Rue-Asha repo calls it pinned to a commit SHA.
- New **`.github/workflows/ci.yml`** in this repo: on `pull_request` and
  `push` to `main`, runs `scripts/proof.sh --all` on a GitHub-hosted runner and
  calls the security baseline. No job contacts the Proxmox node or a guest; no
  secret is configured.
- **`scripts/proof.sh`** gains a checkov sensor for Terraform, so the local gate
  and CI run the same set (CI is just another caller of `proof.sh`).
- **Local commit gate moves from Claude Code to git**: a tracked
  `.githooks/pre-commit` runs `scripts/proof.sh --staged` for every commit —
  Rue's and the agent's alike. `.claude/hooks/iac-proof-gate.sh` is replaced by
  a small hook that only blocks the agent from bypassing it (`--no-verify`).
  CI is the authority; the git hook is fast feedback.
- **Dependabot** config to keep pinned action SHAs and the
  baseline SHA current.
- Branch protection on `main` requiring the CI checks. ⚠ a GitHub settings
  change, applied by hand.

## Capabilities

### New Capabilities
- `ci-pipeline`: the CI verdict for this repo — triggers, what runs, the
  no-network/no-secret constraint, and that it is a required merge check.
- `ci-security-baseline`: the shared reusable workflow in `Rue-Asha/ci` — its
  checks, its interface, and how callers pin it.

### Modified Capabilities
- `agent-harness`: the proof sensor set gains checkov for Terraform changes,
  `--all` mode is declared the CI entry point, and the commit gate becomes a
  git `pre-commit` hook for everyone instead of a Claude Code hook for the agent.

## Non-Goals

- **CD.** No playbook run, `terraform plan`, or `apply` from GitHub Actions. The
  runner cannot reach the LAN, and state stays local.
- **Molecule / role convergence tests.** Highest-value future addition, largest
  single piece — separate change.
- Centralising the node-app or IaC pipelines. Only the security baseline is
  shared now; the rest is extracted when a second consumer exists.
- Life-Manager's CI — that is `ci-life-manager` in its own repo (it consumes the
  baseline built here).

## Done criteria

- [ ] A PR to this repo shows `proof` and `security-baseline` checks, both green.
- [ ] A PR that breaks `terraform fmt` shows a red `proof` check naming `TERRAFORM_FMT_FAILED`.
- [ ] `main` cannot be merged into while a required check is red.
- [ ] `Rue-Asha/ci` exists, and both this repo and `Rue-Asha.github.io` call its baseline by SHA.
- [ ] `scripts/proof.sh --all` runs checkov locally and in CI.
- [ ] A commit by Rue from the terminal with a lint failure is blocked by the git hook.
- [ ] An agent `git commit --no-verify` is blocked; `iac-proof-gate.sh` is gone.

## Appetite

Two evenings.

## Impact

- New: `.github/workflows/ci.yml`, `.github/dependabot.yml`, `ci/requirements.txt`,
  `.githooks/pre-commit`, `.claude/hooks/iac-no-verify-gate.sh`, repo `Rue-Asha/ci`.
- Modified: `scripts/proof.sh`, `.envrc`, `.claude/settings.json`,
  `openspec/specs/agent-harness/spec.md`, README and CLAUDE.md harness sections.
- Removed: `.claude/hooks/iac-proof-gate.sh`.
- External: GitHub repo creation and branch-protection settings (outside the
  machine — confirm before doing).
- `Rue-Asha.github.io/publish.yml` adopts the baseline (one job added) — small
  cross-repo edit.
