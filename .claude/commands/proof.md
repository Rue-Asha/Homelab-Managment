---
description: Run the repo's proof sensors (lint, validate, syntax-check) and report pass/fail per sensor
argument-hint: "[all]"
---

Run `scripts/proof.sh` from the repo root and report what it proved.

Arguments: $ARGUMENTS

- If the arguments ask for everything (`all`, `--all`, "whole repo"), run
  `scripts/proof.sh --all`. Otherwise run `scripts/proof.sh` — staged files only.
- If it prints `proof: nothing to check`, say so in one line and stop. Suggest
  `/proof all` if nothing is staged.

Don't fix anything, and don't run anything else — this command only reports.
`/fix` is the one that repairs.

## Report

One line per sensor, in the order the script ran them:

```
✓ terraform fmt
✗ ansible-lint — ANSIBLE_LINT_FAILED
```

Then, for each failure, the relevant part of the tool output (the offending
file, line, and rule — not the whole log). End with the script's
`proof: N sensor(s), M failed` line.
