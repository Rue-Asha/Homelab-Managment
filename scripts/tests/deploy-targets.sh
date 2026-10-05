#!/usr/bin/env bash
# Fixture tests for scripts/deploy-targets.sh, run by proof.sh. Builds a
# throwaway git repo with a small synthetic ansible/ tree, commits one change
# per scenario from the continuous-deployment spec and compares the output.
# Synthetic rather than a copy of ansible/, so adding a real service never
# changes what these scenarios expect.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

# A git hook exports these; left set they would point the fixture repo at ours.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

repo=$(mktemp -d)
err=$(mktemp)
trap 'command rm -rf "$repo" "$err"' EXIT

git() { command git -C "$repo" -c user.name=fixture -c user.email=fixture@localhost -c core.hooksPath=/dev/null "$@"; }

mkdir -p "$repo/scripts" "$repo/ansible"
command cp -f scripts/deploy-targets.sh "$repo/scripts/"

# put <path> <content>
put() {
  mkdir -p "$(dirname "$repo/$1")"
  printf '%s\n' "$2" >"$repo/$1"
}

role() {
  put "ansible/roles/$1/tasks/main.yml" '--- []'
  put "ansible/roles/$1/meta/main.yml" "---
dependencies: [${2:-}]"
}

# play <path> <hosts> <roles>
play() {
  put "$1" "---
- name: Fixture play
  hosts: $2
  roles: [$3]"
}

put ansible/ansible.cfg '[defaults]
inventory = inventory/
roles_path = ./roles'
put ansible/collections/requirements.yml '---
collections: []'
put ansible/inventory/hosts.yml '---
all:
  children:
    proxmox_guest:
      children:
        life_manager: {hosts: {life-manager01: {}}}
        static_site: {hosts: {static01: {}}}
        github_runner: {hosts: {runner01: {}}}
        pihole: {hosts: {pihole01: {}}}
      hosts: {bare01: {}}
    proxmox_node: {hosts: {proxmox1: {}}}'
put ansible/inventory/group_vars/all.yml '--- {}'
put ansible/inventory/group_vars/proxmox_guest/vars.yml '--- {}'
put ansible/inventory/group_vars/static_site.yml '--- {}'
put ansible/inventory/group_vars/pihole.yml '--- {}'
put ansible/inventory/host_vars/life-manager01/vars.yml 'life_manager_version: v1'
put ansible/inventory/host_vars/pihole01/vars.yml 'pihole_version: v6'
put ansible/inventory/host_vars/static01.yml '--- {}'
role common
role nodejs
role nginx
role life_manager
role proxy_site nginx
role egress_firewall
role github_runner
role pihole
play ansible/playbooks/03_SERVICES/life-manager.yml life_manager 'common, nodejs, life_manager, nginx'
play ansible/playbooks/03_SERVICES/static-site.yml static_site 'common, proxy_site'
play ansible/playbooks/03_SERVICES/batch-job.yml static_site 'nodejs'
play ansible/playbooks/03_SERVICES/pihole.yml pihole 'common, pihole'
play ansible/playbooks/02_BASE_CONFIGURATION/deploy_runner.yml github_runner 'common, egress_firewall, github_runner'
put README.md fixture
put terraform/main.tf '# fixture'

git init -q
git add -A
git commit -qm base

SVC=ansible/playbooks/03_SERVICES
LIFE=$SVC/life-manager.yml
STATIC=$SVC/static-site.yml
PIHOLE=$SVC/pihole.yml
BATCH=$SVC/batch-job.yml
ALL="$BATCH
$LIFE
$PIHOLE
$STATIC"

failed=0

# expect <scenario> <expected output> <deploy-targets args...>
expect() {
  local name=$1 want=$2 got
  shift 2
  got=$(cd "$repo" && ANSIBLE_CONFIG="$repo/ansible/ansible.cfg" scripts/deploy-targets.sh "$@" 2>&1)
  if [ "$got" = "$want" ]; then
    echo "ok: $name"
  else
    echo "FAIL: $name"
    echo "  want: ${want//$'\n'/ }"
    echo "  got:  ${got//$'\n'/ }"
    failed=1
  fi
}

# expect_split <scenario> <status> <stdout> <stderr> <deploy-targets args...>
expect_split() {
  local name=$1 want_status=$2 want_out=$3 want_err=$4 got_out got_err got_status
  shift 4
  got_out=$(cd "$repo" && ANSIBLE_CONFIG="$repo/ansible/ansible.cfg" scripts/deploy-targets.sh "$@" 2>"$err")
  got_status=$?
  got_err=$(<"$err")
  if [ "$got_status" = "$want_status" ] && [ "$got_out" = "$want_out" ] && [ "$got_err" = "$want_err" ]; then
    echo "ok: $name"
  else
    echo "FAIL: $name"
    echo "  want: status $want_status, stdout ${want_out//$'\n'/ }, stderr ${want_err//$'\n'/ }"
    echo "  got:  status $got_status, stdout ${got_out//$'\n'/ }, stderr ${got_err//$'\n'/ }"
    failed=1
  fi
}

# commit <scenario> <file>... -- appends to each file and commits; sets $before
commit() {
  local name=$1 f
  shift
  before=$(git rev-parse HEAD)
  for f in "$@"; do
    printf '# %s\n' "$name" >>"$repo/$f"
  done
  git add -A
  git commit -qm "$name"
}

# change <scenario> <expected output> <file>... -- commits, diffs
change() {
  local name=$1 want=$2
  shift 2
  commit "$name" "$@"
  expect "$name" "$want" "$before" "$(git rev-parse HEAD)"
}

# created <scenario> <created hosts> <status> <stdout> <stderr> <file>... -- commits, diffs with --created
created() {
  local name=$1 hosts=$2 status=$3 out=$4 stderr=$5
  shift 5
  commit "$name" "$@"
  expect_split "$name" "$status" "$out" "$stderr" --created "$hosts" "$before" "$(git rev-parse HEAD)"
}

change "version bump runs only its service" "$LIFE" ansible/inventory/host_vars/life-manager01/vars.yml
change "shared role runs every playbook using it, incl. via meta deps" "$LIFE
$STATIC" ansible/roles/nginx/tasks/main.yml
change "README and terraform deploy nothing" "" README.md terraform/main.tf
change "playbook file runs itself" "$BATCH" "$BATCH"
change "host_vars as a file maps to its host" "$BATCH
$STATIC" ansible/inventory/host_vars/static01.yml
change "group_vars maps to every playbook with a host in the group" "$BATCH
$STATIC" ansible/inventory/group_vars/static_site.yml
change "parent group_vars reach every child group" "$ALL" ansible/inventory/group_vars/proxmox_guest/vars.yml
change "group_vars/all reaches every playbook" "$ALL" ansible/inventory/group_vars/all.yml
change "ansible.cfg runs everything" "$ALL" ansible/ansible.cfg
change "collection requirements run everything" "$ALL" ansible/collections/requirements.yml
change "common runs its services, never the runner playbook" "$LIFE
$PIHOLE
$STATIC" ansible/roles/common/tasks/main.yml
change "Scenario: Role change runs only the pihole playbook" "$PIHOLE" ansible/roles/pihole/tasks/main.yml
change "Scenario: Version bump runs only the pihole playbook" "$PIHOLE" ansible/inventory/host_vars/pihole01/vars.yml
change "Scenario: Group vars of the pihole group run the pihole playbook" "$PIHOLE" ansible/inventory/group_vars/pihole.yml
change "Scenario: A terraform-only diff deploys nothing" "" terraform/main.tf
change "Scenario: A diff touching two services runs both" "$LIFE
$PIHOLE" ansible/inventory/host_vars/pihole01/vars.yml ansible/inventory/host_vars/life-manager01/vars.yml
change "runner roles deploy nothing" "" ansible/roles/github_runner/tasks/main.yml ansible/roles/egress_firewall/tasks/main.yml
change "runner playbook deploys nothing" "" ansible/playbooks/02_BASE_CONFIGURATION/deploy_runner.yml

expect "zero before runs everything" "$ALL" 0000000000000000000000000000000000000000 "$(git rev-parse HEAD)"
expect "non-ancestor before runs everything" "$ALL" "$(git commit-tree 'HEAD^{tree}' -m unrelated)" "$(git rev-parse HEAD)"
expect "named playbook" "$STATIC" static-site
expect "named playbook with extension" "$STATIC" static-site.yml
expect "--all" "$ALL" --all
USAGE='usage: scripts/deploy-targets.sh [--created "<host> ..."] <before> <after> | --all | <playbook>'
expect "a path is never a name" "$USAGE" ../02_BASE_CONFIGURATION/deploy_runner

created "Scenario: A created guest selects its service playbook" pihole01 0 "$PIHOLE" "" terraform/main.tf
created "Scenario: Created guest and diff selections are merged" pihole01 0 "$LIFE
$PIHOLE" "" ansible/inventory/host_vars/life-manager01/vars.yml
created "Scenario: A playbook selected twice runs once" pihole01 0 "$PIHOLE" "" ansible/inventory/host_vars/pihole01/vars.yml
created "Scenario: A created guest without a service playbook" bare01 0 "$LIFE" \
  "deploy-targets: bare01 has no 03_SERVICES playbook" ansible/inventory/host_vars/life-manager01/vars.yml
created "Scenario: A created runner is never deployed" runner01 0 "" \
  "deploy-targets: runner01 has no 03_SERVICES playbook" terraform/main.tf
created "Scenario: An unknown created host fails loudly" "pihole01 ghost01" 1 "" \
  "deploy-targets: created host not in inventory: ghost01" terraform/main.tf
created "unknown created host fails when the diff runs everything" ghost01 1 "" \
  "deploy-targets: created host not in inventory: ghost01" ansible/ansible.cfg
created "Scenario: An empty created list changes nothing" "" 0 "$LIFE" "" ansible/inventory/host_vars/life-manager01/vars.yml
created "several created guests select each of their playbooks" "pihole01  life-manager01" 0 "$LIFE
$PIHOLE" "" terraform/main.tf
expect_split "unknown created host fails when before is zero" 1 "" "deploy-targets: created host not in inventory: ghost01" \
  --created ghost01 0000000000000000000000000000000000000000 "$(git rev-parse HEAD)"
expect_split "Scenario: Created guests are refused outside the diff form (--all)" 64 "" "$USAGE" --created pihole01 --all
expect_split "Scenario: Created guests are refused outside the diff form (name)" 64 "" "$USAGE" --created pihole01 static-site

before=$(git rev-parse HEAD)
git rm -q "$STATIC"
printf '# deleted\n' >>"$repo/ansible/roles/common/tasks/main.yml"
git add -A
git commit -qm "delete a playbook"
expect "deleted playbook is skipped" "$LIFE
$PIHOLE" "$before" "$(git rev-parse HEAD)"

[ "$failed" -eq 0 ]
