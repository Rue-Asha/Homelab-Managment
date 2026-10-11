#!/usr/bin/env bash
# Fixture tests for the guest-side sqlite-snapshot script and its wiring, run by proof.sh.

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


script=$PWD/ansible/roles/sqlite_snapshot/files/sqlite-snapshot

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

# Stub sqlite3: a "database" is a text file with user_version=N and optional migration=NAME lines.
# A failing .backup leaves a partial file at the destination, like a real mid-backup error.
mkdir -p "$dir/bin"
cat >"$dir/bin/sqlite3" <<'STUB'
#!/usr/bin/env bash
cmds=()
while [ $# -gt 0 ]; do
  case $1 in
    -cmd) cmds+=("$2"); shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
db=$1 sql=$2
echo "cmds=${cmds[*]} db=$db sql=$sql" >>"$SQLITE_STUB_LOG"
case $sql in
  ".backup '"*"'")
    dest=${sql#".backup '"}
    dest=${dest%\'}
    [ -z "${SQLITE_STUB_FAIL:-}" ] || { head -c 4 "$db" >"$dest"; echo "database is locked" >&2; exit 5; }
    cp "$db" "$dest"
    ;;
  "PRAGMA user_version"*) sed -n 's/^user_version=//p' "$db" ;;
  "SELECT name FROM sqlite_master"*) grep -q '^migration=' "$db" && echo schema_migrations ;;
  "SELECT name FROM schema_migrations"*"ORDER BY name DESC LIMIT 1"*) sed -n 's/^migration=//p' "$db" | sort -r | head -n1 ;;
  *) echo "stub sqlite3: unhandled: $sql" >&2; exit 2 ;;
esac
exit 0
STUB
chmod +x "$dir/bin/sqlite3"

# fixture <name> [release]   fresh dir with config; sets conf, snap, db, SQLITE_STUB_LOG
fixture() {
  local f=$dir/$1
  mkdir -p "$f"
  snap=$f/snap
  db=$f/app.db
  conf=$f/conf
  export SQLITE_STUB_LOG=$f/sqlite3.log
  : >"$SQLITE_STUB_LOG"
  {
    echo "SERVICE=demo"
    echo "RELEASE_LINK=${2-$f/current}"
    echo "SNAPSHOT_DIR=$snap"
    echo "KEEP_PRE_DEPLOY=10"
    echo "DATABASE=$db"
  } >"$conf"
  export SQLITE_SNAPSHOT_CONF=$conf
  export PATH=$dir/bin:$PATH
  unset SQLITE_STUB_FAIL
}

mkdb() {
  local f=$1 v=$2
  shift 2
  printf 'user_version=%s\n' "$v" >"$f"
  while [ $# -gt 0 ]; do echo "migration=$1" >>"$f"; shift; done
}
mkrelease() { mkdir -p "$1/current" && echo "$2" >"$1/current/.deployed_version"; }

t_pre_deploy_written() (
  fixture written
  mkdb "$db" 4
  out=$("$script" pre-deploy 2>"$dir/written/err") || return 1
  [[ $out =~ ^$snap/pre-deploy/app-[0-9]{8}T[0-9]{6}Z\.db$ ]] || { echo "stdout: $out"; return 1; }
  [ -f "$out" ] && [ -f "${out%.db}.meta" ] || { echo "missing .db or .meta"; return 1; }
  grep -q "sql=.backup '" "$SQLITE_STUB_LOG" || { echo "no .backup call"; return 1; }
  grep -q 'timeout' "$SQLITE_STUB_LOG" || { echo "no busy timeout"; return 1; }
)

t_first_deploy() (
  fixture first
  "$script" pre-deploy >"$dir/first/out" 2>"$dir/first/err" || { echo "exit $?"; return 1; }
  grep -qx "skip: $db does not exist yet" "$dir/first/err" || { echo "stderr: $(cat "$dir/first/err")"; return 1; }
  [ ! -s "$dir/first/out" ] || { echo "stdout not empty"; return 1; }
  [ -z "$(find "$snap" -type f 2>/dev/null)" ] || { echo "files written"; return 1; }
)

t_failed_snapshot() (
  fixture failed
  mkdb "$db" 1
  [ -x "$script" ] || return 1
  export SQLITE_STUB_FAIL=1
  if "$script" pre-deploy >/dev/null 2>&1; then echo "exited 0"; return 1; fi
  [ -z "$(find "$snap" -type f 2>/dev/null)" ] || { find "$snap" -type f; return 1; }
)

t_keep_ten() (
  fixture keep
  mkdb "$db" 1
  mkdir -p "$snap/pre-deploy"
  for i in 01 02 03 04 05 06 07 08 09 10; do
    touch "$snap/pre-deploy/app-202001${i}T000000Z.db" "$snap/pre-deploy/app-202001${i}T000000Z.meta"
  done
  "$script" pre-deploy >/dev/null 2>&1 || return 1
  [ "$(find "$snap/pre-deploy" -name '*.db' | wc -l)" -eq 10 ] || { echo "db count"; return 1; }
  [ "$(find "$snap/pre-deploy" -name '*.meta' | wc -l)" -eq 10 ] || { echo "meta count"; return 1; }
  [ ! -e "$snap/pre-deploy/app-20200101T000000Z.db" ] || { echo "oldest kept"; return 1; }
  [ -e "$snap/pre-deploy/app-20200110T000000Z.db" ] || { echo "newer old one lost"; return 1; }
)

t_meta_migrated() (
  fixture migrated "$dir/migrated/rel/current"
  mkrelease "$dir/migrated/rel" v0.6.0
  mkdb "$db" 4 0002_players.sql 0003_wavelength.sql 0001_init.sql
  out=$("$script" pre-deploy 2>/dev/null) || return 1
  meta=${out%.db}.meta
  head -n1 "$meta" | grep -Eq '^timestamp=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || { cat "$meta"; return 1; }
  want="host=$(hostname)
service=demo
database=$db
kind=pre-deploy
release=v0.6.0
user_version=4
schema_migration=0003_wavelength.sql"
  [ "$(tail -n +2 "$meta")" = "$want" ] || { cat "$meta"; return 1; }
)

t_meta_no_migrations() (
  fixture nomig
  mkdb "$db" 2
  out=$("$script" pre-deploy 2>/dev/null) || return 1
  meta=${out%.db}.meta
  grep -qx 'user_version=2' "$meta" || { cat "$meta"; return 1; }
  ! grep -q '^schema_migration' "$meta" || { cat "$meta"; return 1; }
)

t_release_unknown() (
  fixture unknown "$dir/unknown/nowhere"
  mkdb "$db" 1
  out=$("$script" pre-deploy 2>/dev/null) || { echo "snapshot failed"; return 1; }
  grep -qx 'release=unknown' "${out%.db}.meta" || { cat "${out%.db}.meta"; return 1; }
  mkdir -p "$dir/unknown/nowhere"
  out=$("$script" pre-deploy 2>/dev/null) || { echo "link without marker failed"; return 1; }
  grep -qx 'release=unknown' "${out%.db}.meta" || { cat "${out%.db}.meta"; return 1; }
)

t_db_missing() (
  fixture missing
  local k
  [ -x "$script" ] || return 1
  for k in daily; do
    if "$script" "$k" >/dev/null 2>"$dir/missing/err"; then echo "$k exited 0"; return 1; fi
    [ -s "$dir/missing/err" ] || { echo "$k: no message"; return 1; }
  done
  [ -z "$(find "$snap" -type f 2>/dev/null)" ] || { echo "files written"; return 1; }
)

t_restore_db_missing() (
  fixture restoremissing
  local other=$dir/restoremissing/other.db out
  echo "DATABASE=$other" >>"$conf"
  mkdb "$other" 1
  out=$("$script" pre-restore 2>"$dir/restoremissing/err") || { echo "exit $?: $(cat "$dir/restoremissing/err")"; return 1; }
  grep -qx "skip: $db does not exist" "$dir/restoremissing/err" || { echo "stderr: $(cat "$dir/restoremissing/err")"; return 1; }
  case $out in */other-*.db) [ -f "$out" ] || { echo "no file: $out"; return 1; } ;; *) echo "stdout: $out"; return 1 ;; esac
  command rm -f "$other"
  out=$("$script" pre-restore 2>/dev/null) || { echo "all missing: exit $?"; return 1; }
  [ -z "$out" ] || { echo "stdout: $out"; return 1; }
)

t_daily_keeps_newest() (
  fixture daily
  mkdb "$db" 1
  mkdir -p "$snap/daily"
  touch "$snap/daily/app-20200101T000000Z.db" "$snap/daily/app-20200101T000000Z.meta"
  out=$("$script" daily 2>/dev/null) || return 1
  [ "$(find "$snap/daily" -name '*.db' | wc -l)" -eq 1 ] && [ -f "$out" ] || { ls "$snap/daily"; return 1; }
  [ "$(find "$snap/daily" -name '*.meta' | wc -l)" -eq 1 ] || return 1
  grep -qx 'kind=daily' "${out%.db}.meta"
)

t_list() (
  fixture list
  mkdir -p "$snap/pre-deploy"
  touch "$snap/pre-deploy/app-20200102T000000Z.db" "$snap/pre-deploy/app-20200101T000000Z.db" "$snap/pre-deploy/app-20200101T000000Z.meta"
  [ "$("$script" list pre-deploy 2>/dev/null)" = "app-20200101T000000Z.db
app-20200102T000000Z.db" ]
)

# Applies the role to a local fixture host without a registry entry; every role task must be skipped.
t_role_skips() (
  f=$dir/role
  mkdir -p "$f"
  printf 'fixture ansible_connection=local\n' >"$f/inventory"
  printf '[defaults]\nroles_path=%s/ansible/roles\nlocalhost_warning=False\n' "$PWD" >"$f/ansible.cfg"
  cat >"$f/play.yml" <<'PLAY'
- hosts: all
  gather_facts: false
  roles:
    - sqlite_snapshot
PLAY
  ANSIBLE_CONFIG=$f/ansible.cfg ANSIBLE_PYTHON_INTERPRETER=auto_silent ansible-playbook --check -v -i "$f/inventory" "$f/play.yml" >"$f/out" 2>&1 || { cat "$f/out"; return 1; }
  python3 - "$f/out" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
tasks = 0
for i, line in enumerate(lines):
    if line.startswith("TASK [sqlite_snapshot"):
        tasks += 1
        # check mode alone makes a command report "skipping:", so require the when: verdict
        nxt = next((l for l in lines[i + 1:] if l.startswith(("skipping:", "changed:", "ok:", "fatal:"))), "")
        if not (nxt.startswith("skipping:") and "Conditional result was False" in nxt):
            sys.exit(f"not skipped by its condition: {line} -> {nxt}")
if not tasks:
    sys.exit("no sqlite_snapshot task seen")
PY
)

t_role_requires_db_suffix() (
  f=$dir/suffix
  mkdir -p "$f"
  printf 'fixture ansible_connection=local\n' >"$f/inventory"
  printf '[defaults]\nroles_path=%s/ansible/roles\nlocalhost_warning=False\n' "$PWD" >"$f/ansible.cfg"
  cat >"$f/play.yml" <<'PLAY'
- hosts: all
  gather_facts: false
  vars:
    sqlite_backups: {service: x, unit: x.service, owner: x, group: x, databases: [/var/lib/x/data.sqlite]}
  roles:
    - sqlite_snapshot
PLAY
  if ANSIBLE_CONFIG=$f/ansible.cfg ANSIBLE_PYTHON_INTERPRETER=auto_silent ansible-playbook --check -i "$f/inventory" "$f/play.yml" >"$f/out" 2>&1; then
    echo "role accepted data.sqlite"
    return 1
  fi
  grep -q 'must end in .db' "$f/out" && grep -qF /var/lib/x/data.sqlite "$f/out" || { cat "$f/out"; return 1; }
  ! grep -q 'Install the sqlite3 CLI' "$f/out" || { echo "ran past the assert"; return 1; }
)

# Reads the registry and playbooks with python3.
t_registered() (
  python3 - <<'PY'
import sys, yaml
want = {"life-manager01": "/var/lib/life-manager/life-manager.db", "rues-arcade01": "/var/lib/rues-arcade/rues-arcade.db"}
for host, db in want.items():
    reg = yaml.safe_load(open(f"ansible/inventory/host_vars/{host}/vars.yml")).get("sqlite_backups")
    if not reg:
        sys.exit(f"{host}: no sqlite_backups")
    for key in ("service", "unit", "owner", "group"):
        if not reg.get(key):
            sys.exit(f"{host}: {key} missing")
    if reg["databases"] != [db]:
        sys.exit(f"{host}: databases {reg['databases']}")
PY
)

t_playbook_order() (
  python3 - <<'PY'
import sys, yaml
for pb, role in (("life-manager", "life_manager"), ("rues-arcade", "rues_arcade")):
    roles = [r if isinstance(r, str) else r.get("role") for r in yaml.safe_load(open(f"ansible/playbooks/02_SERVICES/{pb}.yml"))[0]["roles"]]
    if "sqlite_snapshot" not in roles or roles.index("sqlite_snapshot") > roles.index(role):
        sys.exit(f"{pb}: sqlite_snapshot not before {role}: {roles}")
PY
)

check "Pre-deploy snapshot is written" t_pre_deploy_written
check "First deploy without a database" t_first_deploy
check "Failed snapshot fails the run" t_failed_snapshot
check "Guest keeps the newest 10 pre-deploy snapshots" t_keep_ten
check "Metadata of a migrated database" t_meta_migrated
check "Database without schema_migrations" t_meta_no_migrations
check "Release version unknown" t_release_unknown
check "Registered database missing in the guest" t_db_missing
check "Restore when the live database is missing" t_restore_db_missing
extra "daily keeps only the newest snapshot" t_daily_keeps_newest
extra "list pre-deploy prints basenames" t_list
check "Guest role skips a host without a registry entry" t_role_skips
check "Role rejects a database path without .db suffix" t_role_requires_db_suffix
check "Life-Manager and Rues-Arcade are registered" t_registered
check "Service playbooks run the snapshot role before the service role" t_playbook_order

exit "$failed"
