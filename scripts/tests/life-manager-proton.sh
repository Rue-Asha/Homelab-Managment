#!/usr/bin/env bash
# Fixture tests for the life_manager role's Proton Calendar support, run by
# proof.sh. Everything is offline: the download is a file:// artifact that is
# itself a stub logging its calls (so running the installed bin shows up in
# calls.log), a stub `proton` on PATH does the same, and the role is a temp copy whose root:root
# ownership and restart handler are swapped for the current user and a counter.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

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

cases=0
new_case() {
  cases=$((cases + 1))
  FX=$dir/case-$cases
  mkdir -p "$FX"
  export FX
  bad=0
}

# a <command...>   records a failed assertion without leaving the scenario
a() { "$@" || { echo "assertion failed: $*"; bad=1; }; }
has() { grep -qF -- "$2" "$1"; }
not_has() { ! grep -qF -- "$2" "$1"; }

role=ansible/roles/life_manager
me=$(id -un)
mygroup=$(id -gn)

printf '[defaults]\nroles_path=%s/roles\nlocalhost_warning=False\n' "$dir" >"$dir/ansible.cfg"
printf 'fixture ansible_connection=local ansible_python_interpreter=auto_silent\n' >"$dir/inventory"
export ANSIBLE_CONFIG=$dir/ansible.cfg

# --- the role under test -----------------------------------------------------

# The copy differs in two ways only: the tasks chown to the current user (the
# test does not run as root) and the handler counts restarts instead of
# calling systemd.
mkdir -p "$dir/roles"
command cp -r "$role" "$dir/roles/life_manager"
for f in "$dir"/roles/life_manager/tasks/*.yml; do
  sed -i -e 's/^\( *\)owner: root$/\1owner: "{{ fx_user }}"/' -e 's/^\( *\)group: root$/\1group: "{{ fx_group }}"/' "$f"
done
cat >"$dir/roles/life_manager/handlers/main.yml" <<'YML'
- name: Restart life-manager
  ansible.builtin.shell: echo restart >>"{{ fx_restart_log }}"
  changed_when: true
YML

# The play follows the order tasks/main.yml gives the proton import: it is read
# from the real file, so an unwired or misplaced import fails the scenarios.
python3 - "$role/tasks/main.yml" "$dir/flow.yml" <<'PY'
import sys, yaml

def fail(msg):
    play = [{"name": "main.yml wiring", "hosts": "fixture", "gather_facts": False,
             "tasks": [{"name": "Fail", "ansible.builtin.fail": {"msg": msg}}]}]
    yaml.safe_dump(play, open(sys.argv[2], "w"))
    sys.exit(0)

tasks = yaml.safe_load(open(sys.argv[1]))
files = [t.get("ansible.builtin.import_tasks") for t in tasks]
if "proton.yml" not in files:
    fail("tasks/main.yml does not import proton.yml")
i = files.index("proton.yml")
if not ("directories.yml" in files and "config.yml" in files
        and files.index("directories.yml") < i < files.index("config.yml")):
    fail("proton.yml must be imported after directories.yml and before config.yml")
when = tasks[i].get("when")
if not when:
    fail("the proton.yml import has no when")
play = [{"name": "Run the life_manager role's proton and config steps", "hosts": "fixture",
         "gather_facts": True, "gather_subset": ["min"],
         "tasks": [
             {"name": "Proton tasks", "ansible.builtin.include_role": {"name": "life_manager", "tasks_from": "proton.yml"}, "when": when},
             {"name": "Config tasks", "ansible.builtin.include_role": {"name": "life_manager", "tasks_from": "config.yml"}},
             {"name": "Mark the play as finished", "ansible.builtin.debug": {"msg": "flow play finished"}},
         ]}]
yaml.safe_dump(play, open(sys.argv[2], "w"), sort_keys=False)
PY

# --- stub CLI ----------------------------------------------------------------

mkdir -p "$dir/bin"
cat >"$dir/bin/proton" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$FX/calls.log"
exit 0
STUB
chmod +x "$dir/bin/proton"

# --- per-case fixture --------------------------------------------------------

# setup <enabled>   a fresh case with an artifact and its matching sha256
setup() {
  new_case
  mkdir -p "$FX/usr" "$FX/etc" "$FX/data"
  : >"$FX/calls.log"
  printf '#!/usr/bin/env bash\necho "$*" >>"$FX/calls.log"\n' >"$FX/art"
  sha=$(sha256sum "$FX/art" | cut -d' ' -f1)
  write_vars "$1" "$sha"
}

# write_vars <enabled> <sha256>
write_vars() {
  cat >"$FX/vars.yml" <<YML
life_manager_proton_enabled: $1
life_manager_proton_url: file://$FX/art
life_manager_proton_sha256: $2
life_manager_proton_bin: $FX/usr/proton
life_manager_user: $me
life_manager_group: $mygroup
life_manager_data_dir: $FX/data
life_manager_env_file: $FX/etc/env
fx_user: $me
fx_group: $mygroup
fx_restart_log: $FX/restarts
ansible_architecture: x86_64
YML
}

# play [ansible-playbook args...]   runs the flow play; output to a file, never a pipe
play() {
  PATH=$dir/bin:$PATH ansible-playbook -v -i "$dir/inventory" "$dir/flow.yml" -e "@$FX/vars.yml" "$@" >"$FX/play.out" 2>&1
}

recap_changed() { grep -qE "^fixture +: .*changed=$1 " "$FX/play.out"; }
show() { [ "$bad" -eq 0 ] || { echo "--- play"; cat "$FX/play.out"; }; }
restarts() { [ -e "$FX/restarts" ] && wc -l <"$FX/restarts" || echo 0; }
mode_of() { stat -c %a "$1"; }

login_cmd() { echo "sudo -u $me env XDG_CONFIG_HOME=$FX/data/.config $FX/usr/proton account login --profile default"; }

# --- the binary --------------------------------------------------------------

pinned_binary_installed() {
  setup true
  play
  a test $? -eq 0
  a cmp -s "$FX/art" "$FX/usr/proton"
  a test "$(mode_of "$FX/usr/proton")" = 755
  python3 - "$role/tasks/proton.yml" <<'PY' || bad=1
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1])) or []
dl = [t for t in tasks if "ansible.builtin.get_url" in t]
p = dl[0]["ansible.builtin.get_url"] if dl else {}
if len(dl) != 1 or p.get("owner") != "root" or p.get("group") != "root":
    print(f"expected one get_url task owned root:root, got {dl}")
    sys.exit(1)
PY
  show
  return "$bad"
}
check "The pinned binary is installed" pinned_binary_installed

defaults_pinned() {
  new_case
  cat >"$FX/play.yml" <<YML
- name: Render the life_manager role defaults without facts
  hosts: fixture
  gather_facts: false
  vars_files:
    - $PWD/$role/defaults/main.yml
  tasks:
    - name: Write the rendered values
      ansible.builtin.copy:
        dest: $FX/values
        content: "{{ life_manager_proton_enabled | bool | lower }}\n{{ life_manager_proton_version }}\n{{ life_manager_proton_url }}\n{{ life_manager_proton_sha256 }}\n{{ life_manager_proton_bin }}\n"
        mode: "0644"
YML
  ansible-playbook -i "$dir/inventory" "$FX/play.yml" >"$FX/play.out" 2>&1
  a test $? -eq 0
  a test "$(sed -n 1p "$FX/values")" = false
  a test "$(sed -n 2p "$FX/values")" = v5.1.0
  a test "$(sed -n 3p "$FX/values")" = https://github.com/roman-16/proton-cli/releases/download/v5.1.0/proton-cli_linux_amd64
  a test "$(sed -n 4p "$FX/values")" = 51ac1dbb4041a6c5607a0853a7ef405737f497bd207d65e0957b9d4b0c0934d7
  a test "$(sed -n 5p "$FX/values")" = /usr/local/bin/proton
  [ "$bad" -eq 0 ] || { cat "$FX/values" "$FX/play.out"; }
  return "$bad"
}
check "Version, URL, sha256 and bin path are role defaults" defaults_pinned

second_run_unchanged() {
  setup true
  play
  a test $? -eq 0
  play
  a test $? -eq 0
  a recap_changed 0
  a cmp -s "$FX/art" "$FX/usr/proton"
  show
  return "$bad"
}
check "A second run changes nothing" second_run_unchanged

checksum_mismatch() {
  setup true
  write_vars true 0000000000000000000000000000000000000000000000000000000000000000
  printf 'HOST=old\n' >"$FX/etc/env"
  play
  a test $? -ne 0
  a test ! -e "$FX/usr/proton"
  a test "$(cat "$FX/etc/env")" = HOST=old
  a not_has "$FX/play.out" "flow play finished"
  a grep -qiE 'checksum' "$FX/play.out"
  show
  return "$bad"
}
check "A checksum mismatch fails the play before the env is touched" checksum_mismatch

flag_off_inert() {
  setup false
  write_vars false 0000000000000000000000000000000000000000000000000000000000000000
  sed -i "s|^life_manager_proton_url:.*|life_manager_proton_url: http://127.0.0.1:9/never|" "$FX/vars.yml"
  printf 'existing\n' >"$FX/usr/proton"
  play
  a test $? -eq 0
  a test "$(cat "$FX/usr/proton")" = existing
  a test ! -e "$FX/data/.config"
  a not_has "$FX/play.out" "127.0.0.1:9"
  a has "$FX/play.out" "flow play finished"
  show
  return "$bad"
}
check "The flag off downloads and removes nothing" flag_off_inert

non_x86_64_fails() {
  setup true
  play -e ansible_architecture=aarch64
  a test $? -ne 0
  a has "$FX/play.out" aarch64
  a test ! -e "$FX/usr/proton"
  a not_has "$FX/play.out" "censored"
  show
  return "$bad"
}
check "A non-x86_64 host fails with a message naming the architecture" non_x86_64_fails

# --- the env file ------------------------------------------------------------

# Rendered from the real template and from the pre-change content, both through
# the template module so ansible_managed is the same.
cat >"$dir/baseline.j2" <<'J2'
# {{ ansible_managed }}
# Environment for the life-manager service (read by the systemd unit).
HOST={{ life_manager_host }}
PORT={{ life_manager_port }}
NODE_ENV={{ life_manager_node_env }}
DATABASE_PATH={{ life_manager_db_path }}
PROTOCOL_HEADER={{ life_manager_protocol_header }}
J2

# render <enabled>   writes $FX/env.<enabled> and $FX/baseline.<enabled>
render() {
  cat >"$FX/render.yml" <<YML
- name: Render env.j2 and the pre-change baseline
  hosts: fixture
  gather_facts: false
  vars_files:
    - $PWD/$role/defaults/main.yml
  tasks:
    - name: Render the role template
      ansible.builtin.template:
        src: $PWD/$role/templates/env.j2
        dest: $FX/env.$1
        mode: "0644"
    - name: Render the baseline
      ansible.builtin.template:
        src: $dir/baseline.j2
        dest: $FX/baseline.$1
        mode: "0644"
YML
  ansible-playbook -i "$dir/inventory" "$FX/render.yml" -e "life_manager_proton_enabled=$1" >"$FX/render.out" 2>&1
}

flag_on_three_lines() {
  new_case
  render true
  a test $? -eq 0
  { cat "$FX/baseline.true"; printf 'PROTON_CLI=/usr/local/bin/proton\nPROTON_PROFILE=default\nXDG_CONFIG_HOME=/var/lib/life-manager/.config\n'; } >"$FX/expected"
  a cmp -s "$FX/expected" "$FX/env.true"
  [ "$bad" -eq 0 ] || { diff "$FX/expected" "$FX/env.true"; cat "$FX/render.out"; }
  return "$bad"
}
check "The flag on adds exactly the three Proton lines" flag_on_three_lines

flag_off_byte_identical() {
  new_case
  render false
  a test $? -eq 0
  a cmp -s "$FX/baseline.false" "$FX/env.false"
  a test "$(wc -l <"$FX/env.false")" -eq 7
  [ "$bad" -eq 0 ] || { diff "$FX/baseline.false" "$FX/env.false"; cat "$FX/render.out"; }
  return "$bad"
}
check "The flag off renders today's file byte for byte" flag_off_byte_identical

env_change_restarts_once() {
  setup true
  printf '# old\nHOST=127.0.0.1\n' >"$FX/etc/env"
  play
  a test $? -eq 0
  a has "$FX/etc/env" PROTON_CLI=
  a test "$(restarts)" -eq 1
  play
  a test $? -eq 0
  a test "$(restarts)" -eq 1
  python3 - "$role/tasks/config.yml" "$role/handlers/main.yml" <<'PY' || bad=1
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
handlers = yaml.safe_load(open(sys.argv[2]))
if not any(t.get("notify") == "Restart life-manager" for t in cfg) or not any(h.get("name") == "Restart life-manager" for h in handlers):
    print("config.yml must notify the existing Restart life-manager handler")
    sys.exit(1)
PY
  show
  return "$bad"
}
check "An env change restarts the service once" env_change_restarts_once

# --- the session directory and login report ----------------------------------

session_dirs_owner_only() {
  setup true
  play
  a test $? -eq 0
  for d in "$FX/data/.config" "$FX/data/.config/proton-cli"; do
    a test "$(mode_of "$d")" = 700
    a test "$(stat -c %U:%G "$d")" = "$me:$mygroup"
  done
  show
  return "$bad"
}
check "The session directories are created owner-only" session_dirs_owner_only

existing_session_survives() {
  setup true
  mkdir -p "$FX/data/.config/proton-cli/sessions"
  chmod 700 "$FX/data/.config" "$FX/data/.config/proton-cli"
  printf '{"session":"keep"}\n' >"$FX/data/.config/proton-cli/sessions/default.json"
  play
  a test $? -eq 0
  a test "$(cat "$FX/data/.config/proton-cli/sessions/default.json")" = '{"session":"keep"}'
  play
  a test $? -eq 0
  a test "$(cat "$FX/data/.config/proton-cli/sessions/default.json")" = '{"session":"keep"}'
  a recap_changed 0
  show
  return "$bad"
}
check "An existing session survives a run" existing_session_survives

missing_session_warns() {
  setup true
  play
  a test $? -eq 0
  a has "$FX/play.out" "Proton login needed"
  a has "$FX/play.out" "$(login_cmd)"
  a test "$(wc -l <"$FX/calls.log")" -eq 0
  a has "$FX/play.out" "flow play finished"
  show
  return "$bad"
}
check "A missing session prints the login command and the play succeeds" missing_session_warns

present_session_silent() {
  setup true
  mkdir -p "$FX/data/.config/proton-cli/sessions"
  printf '{}\n' >"$FX/data/.config/proton-cli/sessions/default.json"
  play
  a test $? -eq 0
  a not_has "$FX/play.out" "Proton login needed"
  a has "$FX/play.out" "flow play finished"
  show
  return "$bad"
}
check "A present session prints no warning" present_session_silent

check_mode_reports() {
  setup true
  play --check
  a test $? -eq 0
  a has "$FX/play.out" "Proton login needed"
  a has "$FX/play.out" "$(login_cmd)"
  show
  return "$bad"
}
check "Check mode still reports the missing session" check_mode_reports

session_check_cannot_fail() {
  python3 - "$role/tasks" <<'PY'
import sys, yaml

def walk(tasks):
    for t in tasks or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from walk(t.get(k))

d = sys.argv[1]
bad = []
proton = yaml.safe_load(open(f"{d}/proton.yml")) or []
stat_at = [i for i, t in enumerate(proton) if "ansible.builtin.stat" in t and "session" in str(t).lower()]
if not stat_at:
    bad.append("proton.yml has no session stat task")
else:
    for t in proton[stat_at[0]:]:
        if "ansible.builtin.fail" in t or "ansible.builtin.assert" in t or "failed_when" in t or t.get("ignore_errors") is True:
            bad.append(f"session-check task can fail the play: {t.get('name')}")
        if "ansible.builtin.stat" in t and t.get("check_mode") is True:
            bad.append("stat must not need check_mode")
verify = open(f"{d}/verify.yml").read()
if "proton" in verify.lower():
    bad.append("verify.yml mentions Proton")
main = yaml.safe_load(open(f"{d}/main.yml"))
if not any(t.get("ansible.builtin.import_tasks") == "proton.yml" for t in main):
    bad.append("main.yml does not import proton.yml")
if any("proton" in str(t.get("block", "")).lower() for t in main if "block" in t):
    bad.append("main.yml wraps proton in a block")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
}
check "The session check cannot fail the play or trigger a rollback" session_check_cannot_fail

# --- inventory and docs ------------------------------------------------------

host_enables_flag() {
  python3 - <<'PY'
import sys, yaml
v = yaml.safe_load(open("ansible/inventory/host_vars/life-manager01/vars.yml")) or {}
if v.get("life_manager_proton_enabled") is not True:
    print(f"life_manager_proton_enabled is {v.get('life_manager_proton_enabled')!r}, not true")
    sys.exit(1)
PY
}
check "life-manager01 enables the flag" host_enables_flag

readme_documents() {
  local r=$role/README.md m=0
  for v in life_manager_proton_enabled life_manager_proton_version life_manager_proton_url life_manager_proton_sha256 life_manager_proton_bin life_manager_proton_profile; do
    grep -qF "$v" "$r" || { echo "README lacks $v"; m=1; }
  done
  grep -qF "sudo -u life-manager env XDG_CONFIG_HOME=/var/lib/life-manager/.config /usr/local/bin/proton account login --profile default" "$r" || { echo "README lacks the login command"; m=1; }
  grep -qiE '^#+ .*re-?login|^re-?login' "$r" || grep -qiE -B1 '^[-=]{3,}$' "$r" | grep -qi 're-login' || grep -qiE 're-login' "$r" || { echo "README lacks a re-login section"; m=1; }
  grep -qiE 'not (covered|backed up)|not in .?sqlite_backups|not backed up' "$r" || { echo "README lacks the not-backed-up statement"; m=1; }
  return "$m"
}
check "The README holds the variables and the login runbook" readme_documents

exit "$failed"
