#!/usr/bin/env bash
# Prints the 02_SERVICES playbooks a change affects, one per line, for the
# deploy workflow. Reads only git, YAML and the inventory -- never contacts the
# Proxmox node or a guest -- so it runs anywhere proof.sh does. The working
# tree must be at <after>: roles and playbooks are read from it.
#
#   scripts/deploy-targets.sh <before> <after>   playbooks the diff affects
#   scripts/deploy-targets.sh --created "<host> ..." <before> <after>
#                                                plus those targeting guests the apply created
#   scripts/deploy-targets.sh --all              every playbook
#   scripts/deploy-targets.sh <playbook>         one playbook, by name (life-manager)

set -euo pipefail
shopt -s nullglob

cd "$(git rev-parse --show-toplevel)"

export ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-$PWD/ansible/ansible.cfg}"

SERVICES=ansible/playbooks/02_SERVICES
playbooks=("$SERVICES"/*.yml)

usage() {
  echo 'usage: scripts/deploy-targets.sh [--created "<host> ..."] <before> <after> | --all | <playbook>' >&2
  exit 64
}

created=()
if [ "${1:-}" = --created ]; then
  [ $# -eq 4 ] || usage
  # Commits are not checked out: a force-pushed before may no longer exist.
  for arg in "$3" "$4"; do
    [ "$arg" != --all ] && [ ! -f "$SERVICES/${arg%.yml}.yml" ] || usage
  done
  read -ra created <<<"$2"
  shift 2
fi

case $# in
  1)
    if [ "$1" = --all ]; then
      printf '%s\n' "${playbooks[@]}"
      exit 0
    fi
    # A name, never a path: nothing outside 02_SERVICES may be selected.
    case "$1" in */*|'') usage ;; esac
    pb="$SERVICES/${1%.yml}.yml"
    [ -f "$pb" ] || { echo "deploy-targets: no such playbook: $pb" >&2; exit 64; }
    echo "$pb"
    exit 0
    ;;
  2) before=$1 after=$2 ;;
  *) usage ;;
esac

if [ "${#created[@]}" -gt 0 ]; then
  python3 -c '
import json
import subprocess
import sys

listing = subprocess.run(["ansible-inventory", "--list"], stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True)
known = {host for data in json.loads(listing.stdout).values() for host in data.get("hosts", [])}
unknown = [host for host in sys.argv[1:] if host not in known]
for host in unknown:
    print(f"deploy-targets: created host not in inventory: {host}", file=sys.stderr)
sys.exit(1 if unknown else 0)
' "${created[@]}"
fi

everything=false
changed=()
if [[ $before =~ ^0+$ ]] || ! git merge-base --is-ancestor "$before" "$after" 2>/dev/null; then
  everything=true
else
  mapfile -t changed < <(git diff --name-only --no-renames "$before" "$after" -- ansible/)
  for f in "${changed[@]}"; do
    case "$f" in
      ansible/ansible.cfg|ansible/collections/requirements.yml) everything=true ;;
    esac
  done
fi

if $everything && [ "${#created[@]}" -eq 0 ]; then
  printf '%s\n' "${playbooks[@]}"
  exit 0
fi

[ $((${#changed[@]} + ${#created[@]})) -gt 0 ] && [ "${#playbooks[@]}" -gt 0 ] || exit 0

python3 - "$everything" "${#playbooks[@]}" "${playbooks[@]}" "${#created[@]}" "${created[@]}" "${changed[@]}" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

import yaml

args = sys.argv[1:]
everything = args.pop(0) == "true"
count = int(args.pop(0))
playbooks, args = args[:count], args[count:]
count = int(args.pop(0))
created, args = set(args[:count]), args[count:]
changed = [Path(f) for f in args]


def under(prefix):
    """Names directly below ansible/<prefix>/, minus any YAML suffix."""
    base = ("ansible", *prefix.split("/"))
    return {
        f.parts[len(base)].removesuffix(".yml").removesuffix(".yaml")
        for f in changed
        if f.parts[: len(base)] == base and len(f.parts) > len(base)
    }


changed_roles = under("roles")
changed_hosts = under("inventory/host_vars")
changed_groups = under("inventory/group_vars")


def role_names(entries):
    for entry in entries or []:
        yield entry if isinstance(entry, str) else entry.get("role", entry.get("name"))


def roles_of(playbook):
    todo = [role for play in yaml.safe_load(Path(playbook).read_text()) or [] for role in role_names(play.get("roles"))]
    seen = set()
    while todo:
        role = todo.pop()
        if role in seen:
            continue
        seen.add(role)
        meta = Path("ansible/roles", role, "meta/main.yml")
        if meta.exists():
            todo += role_names((yaml.safe_load(meta.read_text()) or {}).get("dependencies"))
    return seen


def ansible(*cmd):
    return subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True).stdout


hosts = {}
playbook = None
listing = False
for line in ansible("ansible-playbook", "--list-hosts", *playbooks).splitlines():
    if line.startswith("playbook: "):
        playbook = line.removeprefix("playbook: ")
        hosts[playbook] = set()
    elif line.strip().startswith("hosts ("):
        listing = True
    elif listing and line.startswith("      ") and line.strip():
        hosts[playbook].add(line.strip())
    else:
        listing = False

inventory = json.loads(ansible("ansible-inventory", "--list"))
parents = {}
direct = {}
for group, data in inventory.items():
    for child in data.get("children", []):
        parents.setdefault(child, set()).add(group)
    for host in data.get("hosts", []):
        direct.setdefault(host, set()).add(group)


def groups_of(host):
    todo = [*direct.get(host, ()), "all"]
    seen = set()
    while todo:
        group = todo.pop()
        if group not in seen:
            seen.add(group)
            todo += parents.get(group, ())
    return seen


for playbook in sorted(playbooks):
    targets = hosts.get(playbook, set())
    if (
        everything
        or Path(playbook) in changed
        or roles_of(playbook) & changed_roles
        or targets & (changed_hosts | created)
        or set().union(*map(groups_of, targets)) & changed_groups
    ):
        print(playbook)

for host in sorted(created - set().union(*hosts.values())):
    print(f"deploy-targets: {host} has no 02_SERVICES playbook", file=sys.stderr)
PY
