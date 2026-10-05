#!/usr/bin/env bash
# Fixture tests for scripts/render-inventory.sh.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

repo=$(mktemp -d)
trap 'command rm -rf "$repo"' EXIT

mkdir -p "$repo/scripts" "$repo/ansible/inventory" "$repo/bin" "$repo/home/.cache/homelab"
command cp -f scripts/render-inventory.sh "$repo/scripts/"

cat >"$repo/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${TF_FIXTURE_MODE:?}" in
  ok)
    printf '%s' "${TF_FIXTURE_OUTPUT:?}"
    ;;
  missing)
    echo 'Error: Output "ansible_inventory" not found' >&2
    exit 1
    ;;
  fail)
    echo 'Error: terraform output failed' >&2
    exit 1
    ;;
esac
EOF
chmod +x "$repo/bin/terraform"

git -C "$repo" init -q

failed=0

expect_ok() {
  local name=$1 mode=$2 expected=$3
  (
    cd "$repo" || exit 1
    TF_FIXTURE_MODE=$mode TF_FIXTURE_OUTPUT='--- from terraform' PATH="$repo/bin:$PATH" HOME="$repo/home" \
      bash scripts/render-inventory.sh
  ) >"$repo/out" 2>"$repo/err"
  local got
  got=$(cat "$repo/ansible/inventory/00-terraform.yml")
  if [ "$got" = "$expected" ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    echo "  wanted: $expected"
    echo "  got:    $got"
    failed=1
  fi
}

expect_fail() {
  local name=$1 mode=$2
  if (
    cd "$repo" || exit 1
    TF_FIXTURE_MODE=$mode PATH="$repo/bin:$PATH" HOME="$repo/home" \
      bash scripts/render-inventory.sh
  ) >"$repo/out" 2>"$repo/err"; then
    echo "FAIL: $name (unexpected success)"
    failed=1
  else
    echo "PASS: $name"
  fi
}

rm -f "$repo/home/.cache/homelab/00-terraform.yml" "$repo/ansible/inventory/00-terraform.yml"
expect_ok "uses terraform output when present" ok '--- from terraform'

printf '%s' '--- from cache' >"$repo/home/.cache/homelab/00-terraform.yml"
rm -f "$repo/ansible/inventory/00-terraform.yml"
expect_ok "falls back to cached inventory when output is missing" missing '--- from cache'

rm -f "$repo/home/.cache/homelab/00-terraform.yml" "$repo/ansible/inventory/00-terraform.yml"
expect_fail "fails when output is missing and no cache exists" missing

exit "$failed"
