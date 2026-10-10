#!/usr/bin/env bash
# Fixture tests for the node-side sqlite-backup script and its wiring, run by proof.sh.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

dir=$(mktemp -d)
trap 'command rm -rf "$dir"' EXIT

failed=0

# check <scenario> <command...>   passes when the command exits 0
check() {
  local name=$1
  shift
  if "$@" >"$dir/out" 2>&1; then
    echo "ok: Scenario: $name"
  else
    echo "FAIL: Scenario: $name (exit $?)"
    sed 's/^/  /' "$dir/out"
    failed=1
  fi
}

# extra <label> <command...>   like check, for assertions that are not a spec scenario
extra() {
  local name=$1
  shift
  if "$@" >"$dir/out" 2>&1; then
    echo "ok: $name"
  else
    echo "FAIL: $name (exit $?)"
    sed 's/^/  /' "$dir/out"
    failed=1
  fi
}

script=$PWD/ansible/roles/sqlite_backup/files/homelab-sqlite-backup
snapdir=/var/backups/sqlite-snapshot
stamp_new=20261011T033012Z

# Stubs. FX points at the current case's fixture dir; a guest's filesystem is
# $FX/guest/<ctid>, and files in $FX switch failure modes per ctid.
mkdir -p "$dir/bin"
cat >"$dir/bin/pct" <<'STUB'
#!/usr/bin/env bash
snap=/var/backups/sqlite-snapshot
case $1 in
  exec)
    ctid=$2 cmd=$4 sub=$5
    g=$FX/guest/$ctid
    [ -e "$FX/fail_exec_$ctid" ] && { echo "container $ctid is not running" >&2; exit 255; }
    mk() {
      mkdir -p "$g$snap/$1"
      f=$g$snap/$1/$2-$3.db
      echo "DB $ctid $2 $1${CORRUPT:+ CORRUPT}" >"$f"
      printf 'timestamp=x\nhost=%s\nservice=%s\nkind=%s\n' "$ctid" "$2" "$1" >"${f%.db}.meta"
      echo "$snap/$1/${f##*/}"
    }
    case $sub in
      daily|pre-restore)
        [ -e "$FX/missing_db_$ctid" ] && { echo "error: database does not exist" >&2; exit 1; }
        [ -e "$FX/corrupt_$ctid" ] && CORRUPT=1
        for stem in $(cat "$FX/stems_$ctid" 2>/dev/null || echo app); do
          mk "$sub" "$stem" "$(cat "$FX/stamp")"
        done ;;
      list)
        for f in "$g$snap/$6"/*.db; do [ -e "$f" ] && echo "${f##*/}"; done
        exit 0 ;;
    esac ;;
  pull)
    echo "$2 $3" >>"$FX/pull.log"
    [ -e "$FX/diskfull_$2" ] && { head -c 4 "$FX/guest/$2$3" >"$4"; echo "no space left on device" >&2; exit 1; }
    cp "$FX/guest/$2$3" "$4" ;;
  *) exit 2 ;;
esac
STUB
cat >"$dir/bin/sqlite3" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$FX/sqlite.log"
if grep -q CORRUPT "$1"; then echo "*** in database main ***"; else echo ok; fi
STUB
cat >"$dir/bin/curl" <<'STUB'
#!/usr/bin/env bash
body=
args=("$@")
for i in "${!args[@]}"; do [ "${args[$i]}" = --data-raw ] && body=${args[$((i + 1))]}; done
echo "${args[-1]} | $body" >>"$FX/curl.log"
[ -e "$FX/curl_fail" ] && { echo "curl: (6) Could not resolve host" >&2; exit 6; }
exit 0
STUB
chmod +x "$dir/bin/pct" "$dir/bin/sqlite3" "$dir/bin/curl"
export PATH="$dir/bin:$PATH"

cases=0
new_case() {
  cases=$((cases + 1))
  FX=$dir/case-$cases
  mkdir -p "$FX/guest" "$FX/root"
  export FX
  echo "$stamp_new" >"$FX/stamp"
  ping=https://hc-ping.test/uuid-1234
  bad=0
}

# write_conf <"host ctid">...
write_conf() {
  {
    echo "BACKUP_ROOT=$FX/root"
    echo KEEP_DAILY=14
    echo KEEP_PRE_DEPLOY=10
    echo KEEP_PRE_RESTORE=10
    echo "PING_URL=$ping"
    echo "SNAPSHOT_CMD=/usr/local/sbin/sqlite-snapshot"
    echo GUEST_TIMEOUT=30
    local g
    for g in "$@"; do echo "GUEST=$g"; done
  } >"$FX/conf"
}
std_conf() { write_conf "life-manager01 101" "rues-arcade01 102"; }

node() { HOMELAB_SQLITE_BACKUP_CONF=$FX/conf "$script" "$@" >"$FX/stdout" 2>"$FX/stderr"; }

# a <command...>   records a failed assertion without leaving the scenario
a() { "$@" || { echo "assertion failed: $*"; bad=1; }; }
exists() { [ -e "$1" ]; }
absent() { [ ! -e "$1" ]; }
count() { [ "$(find "$1" -maxdepth 1 -type f -name "$2" | wc -l)" -eq "$3" ]; }
has() { grep -qF -- "$2" "$1"; }

# node_snap <host> <kind> <stem> <stamp>   a snapshot already on the node
node_snap() {
  mkdir -p "$FX/root/$1/$2"
  echo "NODE $3 $4" >"$FX/root/$1/$2/$3-$4.db"
  echo "node meta $4" >"$FX/root/$1/$2/$3-$4.meta"
}
# guest_snap <ctid> <kind> <stem> <stamp>   a snapshot already in a guest
guest_snap() {
  mkdir -p "$FX/guest/$1$snapdir/$2"
  echo "GUEST $3 $4" >"$FX/guest/$1$snapdir/$2/$3-$4.db"
  echo "guest meta $4" >"$FX/guest/$1$snapdir/$2/$3-$4.meta"
}
# stamps <from> <to>   20260901T030000Z ... for days from..to
stamps() { local d; for d in $(seq "$1" "$2"); do printf '202609%02dT030000Z\n' "$d"; done; }

# --- 3.1 run: collection ---------------------------------------------------

collects_every_guest() {
  new_case
  std_conf
  node run
  a test $? -eq 0
  local h
  for h in life-manager01 rues-arcade01; do
    a exists "$FX/root/$h/daily/app-$stamp_new.db"
    a exists "$FX/root/$h/daily/app-$stamp_new.meta"
  done
  a has "$FX/stderr" "life-manager01: ok"
  a has "$FX/stderr" "rues-arcade01: ok"
  return "$bad"
}
check "Nightly run collects every registered guest" collects_every_guest

pre_deploy_copied_once() {
  new_case
  write_conf "life-manager01 101"
  guest_snap 101 pre-deploy app 20261001T010000Z
  guest_snap 101 pre-deploy app 20261002T010000Z
  guest_snap 101 pre-deploy app 20261003T010000Z
  node_snap life-manager01 pre-deploy app 20261002T010000Z
  node run
  a test $? -eq 0
  local d=$FX/root/life-manager01/pre-deploy
  a count "$d" '*.db' 3
  a count "$d" '*.meta' 3
  a has "$d/app-20261002T010000Z.db" "NODE app"
  a test "$(grep -c 'pre-deploy/.*\.db$' "$FX/pull.log")" -eq 2
  return "$bad"
}
check "New pre-deploy snapshots are copied once" pre_deploy_copied_once

one_guest_fails() {
  new_case
  std_conf
  touch "$FX/fail_exec_101"
  node run
  a test $? -ne 0
  a grep -qE 'life-manager01: FAILED \(.+\)' "$FX/stderr"
  a has "$FX/stderr" "rues-arcade01: ok"
  a exists "$FX/root/rues-arcade01/daily/app-$stamp_new.db"
  a absent "$FX/root/life-manager01/daily/app-$stamp_new.db"
  return "$bad"
}
check "One guest fails, the others still run" one_guest_fails

database_missing() {
  new_case
  std_conf
  touch "$FX/missing_db_101"
  node run
  a test $? -ne 0
  a has "$FX/stderr" "life-manager01: FAILED"
  a exists "$FX/root/rues-arcade01/daily/app-$stamp_new.db"
  return "$bad"
}
check "Registered database missing in the guest" database_missing

disk_full() {
  new_case
  std_conf
  touch "$FX/diskfull_101"
  node run
  a test $? -ne 0
  a has "$FX/stderr" "life-manager01: FAILED"
  a test -z "$(find "$FX/root/life-manager01" -type f 2>/dev/null)"
  a exists "$FX/root/rues-arcade01/daily/app-$stamp_new.db"
  return "$bad"
}
check "Node disk full" disk_full

meta_travels() {
  new_case
  write_conf "life-manager01 101"
  node run
  a test $? -eq 0
  a cmp -s "$FX/guest/101$snapdir/daily/app-$stamp_new.meta" "$FX/root/life-manager01/daily/app-$stamp_new.meta"
  return "$bad"
}
check "Metadata travels with the snapshot to the node" meta_travels

intact_kept() {
  new_case
  write_conf "life-manager01 101"
  node run
  a test $? -eq 0
  a exists "$FX/root/life-manager01/daily/app-$stamp_new.db"
  a exists "$FX/root/life-manager01/daily/app-$stamp_new.meta"
  a has "$FX/sqlite.log" "PRAGMA integrity_check;"
  return "$bad"
}
check "Intact snapshot is kept" intact_kept

corrupt_discarded() {
  new_case
  std_conf
  touch "$FX/corrupt_101"
  node run
  a test $? -ne 0
  a has "$FX/stderr" "life-manager01: FAILED"
  a test -z "$(find "$FX/root/life-manager01" -type f 2>/dev/null)"
  a exists "$FX/root/rues-arcade01/daily/app-$stamp_new.db"
  return "$bad"
}
check "Corrupt snapshot is discarded" corrupt_discarded

# --- 3.2 rotation and ping -------------------------------------------------

daily_rotation_14() {
  new_case
  write_conf "life-manager01 101"
  local s
  for s in $(stamps 1 14); do node_snap life-manager01 daily app "$s"; done
  node run
  a test $? -eq 0
  local d=$FX/root/life-manager01/daily
  a count "$d" '*.db' 14
  a count "$d" '*.meta' 14
  a absent "$d/app-20260901T030000Z.db"
  a absent "$d/app-20260901T030000Z.meta"
  a exists "$d/app-20260902T030000Z.db"
  a exists "$d/app-$stamp_new.db"
  return "$bad"
}
check "Daily rotation keeps the newest 14" daily_rotation_14

pre_deploy_rotation_10() {
  new_case
  write_conf "life-manager01 101"
  local s
  for s in $(stamps 1 12); do guest_snap 101 pre-deploy app "$s"; done
  node run
  a test $? -eq 0
  local d=$FX/root/life-manager01/pre-deploy
  a count "$d" '*.db' 10
  a count "$d" '*.meta' 10
  a absent "$d/app-20260901T030000Z.db"
  a absent "$d/app-20260902T030000Z.meta"
  a exists "$d/app-20260903T030000Z.db"
  a exists "$d/app-20260912T030000Z.db"
  return "$bad"
}
check "Pre-deploy rotation keeps the newest 10" pre_deploy_rotation_10

fewer_than_14() {
  new_case
  write_conf "life-manager01 101"
  local s
  for s in $(stamps 1 5); do node_snap life-manager01 daily app "$s"; done
  node run
  a test $? -eq 0
  a count "$FX/root/life-manager01/daily" '*.db' 6
  a count "$FX/root/life-manager01/daily" '*.meta' 6
  return "$bad"
}
check "Fewer than 14 present" fewer_than_14

failed_run_deletes_nothing() {
  new_case
  write_conf "life-manager01 101"
  local s
  for s in $(stamps 1 20); do node_snap life-manager01 daily app "$s"; done
  touch "$FX/fail_exec_101"
  node run
  a test $? -ne 0
  a count "$FX/root/life-manager01/daily" '*.db' 20
  a count "$FX/root/life-manager01/daily" '*.meta' 20
  return "$bad"
}
check "Failed run deletes nothing" failed_run_deletes_nothing

ping_success() {
  new_case
  std_conf
  node run
  a test $? -eq 0
  a test "$(wc -l <"$FX/curl.log")" -eq 1
  a test "$(cut -d' ' -f1 "$FX/curl.log")" = "$ping"
  return "$bad"
}
check "All services succeeded" ping_success

ping_failure() {
  new_case
  std_conf
  touch "$FX/fail_exec_102"
  node run
  a test $? -ne 0
  a test "$(wc -l <"$FX/curl.log")" -eq 1
  a test "$(cut -d' ' -f1 "$FX/curl.log")" = "$ping/fail"
  a has "$FX/curl.log" "rues-arcade01"
  a has "$FX/curl.log" "snapshot in guest 102 failed"
  a not_has "$FX/curl.log" "life-manager01"
  return "$bad"
}
not_has() { ! grep -qF -- "$2" "$1"; }
check "A service failed" ping_failure

ping_unreachable() {
  new_case
  std_conf
  touch "$FX/curl_fail"
  node run
  a test $? -eq 0
  a has "$FX/stderr" "ping"
  touch "$FX/fail_exec_101"
  node run
  a test $? -ne 0
  a has "$FX/stderr" "ping"
  return "$bad"
}
check "healthchecks.io unreachable" ping_unreachable

# --- 3.3 locate and pre-restore --------------------------------------------

locate_found() {
  new_case
  std_conf
  node_snap rues-arcade01 pre-deploy app 20261003T010000Z
  node locate rues-arcade01 app-20261003T010000Z.db
  a test $? -eq 0
  a test "$(head -1 "$FX/stdout")" = "$FX/root/rues-arcade01/pre-deploy/app-20261003T010000Z.db"
  a test "$(sed -n '2,$p' "$FX/stdout")" = "node meta 20261003T010000Z"
  a python3 - ansible/playbooks/00_OPERATIONAL/sqlite_restore.yml <<'PY'
import sys, yaml

def flat(tasks):
    for t in tasks:
        yield t
        for k in ("block", "rescue", "always"):
            yield from flat(t.get(k, []))

tasks = list(flat(yaml.safe_load(open(sys.argv[1]))[0]["tasks"]))
locate = next((i for i, t in enumerate(tasks) if "locate" in str(t.get("ansible.builtin.command", ""))), None)
stops = [i for i, t in enumerate(tasks) if "ansible.builtin.systemd" in t and t["ansible.builtin.systemd"].get("state") == "stopped"]
if locate is None or not stops or locate > min(stops):
    sys.exit(f"locate task at {locate}, stop tasks at {stops}")
PY
  return "$bad"
}
check "Snapshot metadata is shown first" locate_found

locate_not_found() {
  new_case
  std_conf
  node_snap rues-arcade01 daily app 20261001T030000Z
  node_snap rues-arcade01 pre-restore app 20261002T030000Z
  node locate rues-arcade01 app-20261009T030000Z.db
  a test $? -eq 1
  a has "$FX/stderr" "not found: app-20261009T030000Z.db"
  a has "$FX/stderr" "daily/app-20261001T030000Z.db"
  a has "$FX/stderr" "pre-restore/app-20261002T030000Z.db"
  a test ! -s "$FX/stdout"
  return "$bad"
}
check "Snapshot name not found" locate_not_found

pre_restore_saves() {
  new_case
  std_conf
  node pre-restore rues-arcade01 102
  a test $? -eq 0
  local d=$FX/root/rues-arcade01/pre-restore
  a exists "$d/app-$stamp_new.db"
  a exists "$d/app-$stamp_new.meta"
  a has "$FX/sqlite.log" "PRAGMA integrity_check;"
  a test "$(tail -1 "$FX/stdout")" = "app-$stamp_new.db"
  a has "$FX/pull.log" "102 "
  a not_has "$FX/pull.log" "101 "
  a absent "$FX/curl.log"
  a absent "$FX/root/life-manager01"
  return "$bad"
}
check "Current database is saved before the restore" pre_restore_saves

pre_restore_needs_ctid() {
  new_case
  std_conf
  node pre-restore rues-arcade01
  a test $? -ne 0
  a absent "$FX/pull.log"
  return "$bad"
}
extra "pre-restore without a container ID fails" pre_restore_needs_ctid

pre_restore_rotation_10() {
  new_case
  std_conf
  local s
  for s in $(stamps 1 10); do node_snap rues-arcade01 pre-restore app "$s"; done
  node pre-restore rues-arcade01 102
  a test $? -eq 0
  local d=$FX/root/rues-arcade01/pre-restore
  a count "$d" '*.db' 10
  a count "$d" '*.meta' 10
  a absent "$d/app-20260901T030000Z.db"
  a absent "$d/app-20260901T030000Z.meta"
  a exists "$d/app-$stamp_new.db"
  return "$bad"
}
check "Pre-restore rotation keeps the newest 10" pre_restore_rotation_10

# --- 3.4 node playbook preflight -------------------------------------------

playbook=ansible/playbooks/00_OPERATIONAL/sqlite_backup.yml
export ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-$PWD/ansible/ansible.cfg}"

# fixture_inv <ping url> <extra guest lines...>   inventory of local hosts
fixture_inv() {
  local ping_url=$1
  shift
  mkdir -p "$FX/inv"
  {
    cat <<YML
all:
  vars:
    ansible_connection: local
    ansible_python_interpreter: "{{ ansible_playbook_python }}"
  children:
    proxmox_node:
      hosts:
        node1:
          sqlite_backup_ping_url: "$ping_url"
    proxmox_guest:
      hosts:
YML
    printf '%s\n' "$@"
  } >"$FX/inv/hosts.yml"
}

GUEST_A='        guest_a:
          lxc_ctid: 101
          sqlite_backups: {service: a, unit: a.service, owner: a, group: a, databases: [/var/lib/a/a.db]}'
GUEST_B='        guest_b:
          lxc_ctid: 102'
GUEST_D='        guest_d:
          lxc_ctid: 103
          sqlite_backups: {service: d, unit: d.service, owner: d, group: d, databases: [/var/lib/d/data.sqlite]}'
GUEST_C='        guest_c:
          sqlite_backups: {service: c, unit: c.service, owner: c, group: c, databases: [/var/lib/c/c.db]}'

# play <extra ansible-playbook args...>   output to a file, never a pipe
play() {
  ansible-playbook -i "$FX/inv/hosts.yml" "$playbook" --check "$@" >"$FX/play.out" 2>&1
}

ping_unset() {
  new_case
  fixture_inv "" "$GUEST_A"
  play
  a test $? -ne 0
  a has "$FX/play.out" "sqlite_backup_ping_url"
  a has "$FX/play.out" "host_vars/proxmox1/vault.yml"
  a not_has "$FX/play.out" "sqlite_backup : Ensure"
  return "$bad"
}
check "Ping URL unset" ping_unset

preflight_ignores_unregistered() {
  new_case
  fixture_inv "https://hc-ping.test/x" "$GUEST_A" "$GUEST_B"
  play --tags preflight
  a test $? -eq 0
  a has "$FX/play.out" "guest_a 101"
  a not_has "$FX/play.out" "guest_b"
  return "$bad"
}
check "Node playbook ignores a host without a registry entry" preflight_ignores_unregistered

registered_without_ctid() {
  new_case
  fixture_inv "https://hc-ping.test/x" "$GUEST_A" "$GUEST_C"
  play
  a test $? -ne 0
  a has "$FX/play.out" "guest_c"
  a has "$FX/play.out" "lxc_ctid"
  a not_has "$FX/play.out" "sqlite_backup : Ensure"
  a not_has "$FX/play.out" "sqlite_backup : Install"
  return "$bad"
}
check "Registered host without a container ID" registered_without_ctid

registered_without_db_suffix() {
  new_case
  fixture_inv "https://hc-ping.test/x" "$GUEST_A" "$GUEST_D"
  play
  a test $? -ne 0
  a has "$FX/play.out" "guest_d"
  a has "$FX/play.out" ".db"
  a not_has "$FX/play.out" "sqlite_backup : Ensure"
  return "$bad"
}
extra "Registered database path without .db suffix" registered_without_db_suffix

restore_refuses_check_mode() {
  new_case
  mkdir -p "$FX/inv"
  cat >"$FX/inv/hosts.yml" <<'YML'
all:
  vars:
    ansible_connection: local
    ansible_python_interpreter: "{{ ansible_playbook_python }}"
    proxmox_node_ip: 127.0.0.1
    ansible_become: false
  children:
    proxmox_guest:
      hosts:
        guest_a:
          lxc_ctid: 101
          sqlite_backups: {service: a, unit: a.service, owner: a, group: a, databases: [/var/lib/a/a.db]}
YML
  ansible-playbook -i "$FX/inv/hosts.yml" ansible/playbooks/00_OPERATIONAL/sqlite_restore.yml --check \
    -e sqlite_restore_snapshot=a-20261001T030000Z.db >"$FX/play.out" 2>&1
  a test $? -ne 0
  a has "$FX/play.out" "has no dry run"
  a not_has "$FX/play.out" "Look up the snapshot"
  return "$bad"
}
extra "Restore playbook refuses --check" restore_refuses_check_mode

deploy_never_runs_node_playbook() {
  a test -f "$playbook"
  a python3 - "$playbook" <<'PY'
import sys, yaml
plays = yaml.safe_load(open(sys.argv[1]))
if [p["hosts"] for p in plays] != ["proxmox_node"]:
    sys.exit(f"node playbook targets {[p['hosts'] for p in plays]}")
PY
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE
  local r=$FX/repo
  mkdir -p "$r/scripts"
  command cp -f scripts/deploy-targets.sh "$r/scripts/"
  command cp -r ansible "$r/ansible"
  command rm -f "$r/ansible/inventory/00-terraform.yml"
  command git -C "$r" init -q
  command git -C "$r" add -A
  command git -C "$r" -c user.name=fixture -c user.email=fixture@localhost -c core.hooksPath=/dev/null commit -qm base
  local before
  before=$(command git -C "$r" rev-parse HEAD)
  printf '\n# touched\n' | tee -a "$r/$playbook" "$r/ansible/roles/sqlite_backup/tasks/main.yml" >/dev/null
  command git -C "$r" -c user.name=fixture -c user.email=fixture@localhost -c core.hooksPath=/dev/null commit -qam change
  local out
  out=$(cd "$r" && ANSIBLE_CONFIG="$r/ansible/ansible.cfg" scripts/deploy-targets.sh "$before" HEAD 2>&1)
  a test $? -eq 0
  ! grep -q sqlite_backup <<<"$out" || { echo "diff selected: $out"; bad=1; }
  out=$(cd "$r" && ANSIBLE_CONFIG="$r/ansible/ansible.cfg" scripts/deploy-targets.sh --all 2>&1)
  ! grep -q sqlite_backup <<<"$out" || { echo "--all selected: $out"; bad=1; }
  ! grep -qv '^ansible/playbooks/02_SERVICES/' <<<"$out" || { echo "--all left 02_SERVICES: $out"; bad=1; }
  (cd "$r" && scripts/deploy-targets.sh sqlite_backup) >/dev/null 2>&1
  a test $? -eq 64
  return "$bad"
}
check "The deploy never runs the node playbook" deploy_never_runs_node_playbook

exit "$failed"
