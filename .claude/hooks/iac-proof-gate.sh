#!/bin/bash
set -euo pipefail

CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CLAUDE_PROJECT_DIR"

# Nur gestagte Dateien prüfen — nicht das ganze Repo bei jedem Commit
STAGED_TF=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.tf$' || true)
STAGED_ANSIBLE=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(yml|yaml)$' || true)

FAILED=0

# --- Terraform-Sensor ---
if [ -n "$STAGED_TF" ]; then
  echo "Terraform-Dateien geändert, prüfe..."

  if ! terraform validate >/tmp/tf-validate.log 2>&1; then
    echo "INVARIANT_VIOLATION: TERRAFORM_VALIDATE_FAILED" >&2
    cat /tmp/tf-validate.log >&2
    FAILED=1
  fi

  if ! tflint >/tmp/tflint.log 2>&1; then
    echo "INVARIANT_VIOLATION: TFLINT_FAILED" >&2
    cat /tmp/tflint.log >&2
    FAILED=1
  fi
fi

# --- Ansible-Sensor ---
if [ -n "$STAGED_ANSIBLE" ]; then
  echo "Ansible-Dateien geändert, prüfe..."

  for file in $STAGED_ANSIBLE; do
    if ! ansible-lint "$file" >/tmp/ansible-lint.log 2>&1; then
      echo "INVARIANT_VIOLATION: ANSIBLE_LINT_FAILED ($file)" >&2
      cat /tmp/ansible-lint.log >&2
      FAILED=1
    fi
  done
fi

if [ "$FAILED" -eq 1 ]; then
  echo "" >&2
  echo "Commit blockiert. Fix die oben genannten Fehler und versuch es erneut." >&2
  exit 2
fi

exit 0
