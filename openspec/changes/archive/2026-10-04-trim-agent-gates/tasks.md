## 1. Trim the gates

- [x] 1.1 Delete `.claude/hooks/iac-no-verify-gate.sh` and its entry in `.claude/settings.json`
- [x] 1.2 Extend `.claude/hooks/iac-apply-gate.sh` to ask before `gh pr merge`, `gh workflow run`, and `gh api` merge/dispatch calls
- [x] 1.3 Update `.claude/CLAUDE.md` and `README.md`
- [x] 1.4 Verify the scenarios by piping each command into the hook
