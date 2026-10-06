#!/usr/bin/env bash
# Fixture tests for scripts/checks/unique-hosts.py, run by proof.sh.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

dir=$(mktemp -d)
trap 'command rm -rf "$dir"' EXIT

failed=0

# expect <scenario> <pass|fail> <tfvars body>
expect() {
  local name=$1 want=$2 got=pass
  printf 'lxc_hosts = {\n%s\n}\n' "$3" >"$dir/h.tfvars"
  python3 scripts/checks/unique-hosts.py "$dir/h.tfvars" >/dev/null 2>&1 || got=fail
  if [ "$got" = "$want" ]; then
    echo "ok: $name"
  else
    echo "FAIL: $name (want $want, got $got)"
    failed=1
  fi
}

host() {
  printf '  "%s" = {\n' "$1"
  [ -z "${3:-}" ] || printf '    vmid = %s\n' "$3"
  printf '    ipv4 = "%s/24"\n  }\n' "$2"
}

expect "distinct ipv4, no vmids" pass "$(host a 192.168.0.1)$(host b 192.168.0.2)"
expect "duplicate ipv4 without vmids" fail "$(host a 192.168.0.1)$(host b 192.168.0.1)"
expect "duplicate ipv4 with distinct vmids" fail "$(host a 192.168.0.1 5)$(host b 192.168.0.1 6)"
expect "duplicate declared vmid" fail "$(host a 192.168.0.1 5)$(host b 192.168.0.2 5)"
expect "one host pins vmid, other omits" pass "$(host a 192.168.0.1 5)$(host b 192.168.0.2)"

exit "$failed"
