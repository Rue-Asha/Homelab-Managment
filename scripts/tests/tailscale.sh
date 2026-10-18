#!/usr/bin/env bash
# Fixture tests for the tailscale role's join logic and its operator playbook,
# run by proof.sh. A stub `tailscale` on PATH stands in for the CLI; nothing
# here contacts a tailnet, the Proxmox node or a guest.

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

printf '[defaults]\nroles_path=%s/ansible/roles\nlocalhost_warning=False\n' "$PWD" >"$dir/ansible.cfg"
printf 'fixture ansible_connection=local ansible_python_interpreter=auto_silent\n' >"$dir/inventory"
export ANSIBLE_CONFIG=$dir/ansible.cfg

# --- defaults ----------------------------------------------------------------

repo_url_defaults_to_trixie() {
  new_case
  cat >"$FX/play.yml" <<YML
- name: Render the tailscale role defaults without facts
  hosts: fixture
  gather_facts: false
  vars_files:
    - $PWD/ansible/roles/tailscale/defaults/main.yml
  tasks:
    - name: Write the rendered URLs
      ansible.builtin.copy:
        dest: $FX/urls
        content: "{{ tailscale_apt_key_url }}\n{{ tailscale_apt_list_url }}\n"
        mode: "0644"
YML
  ansible-playbook -i "$dir/inventory" "$FX/play.yml" >"$FX/play.out" 2>&1
  a test $? -eq 0
  a test "$(sed -n 1p "$FX/urls")" = https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg
  a test "$(sed -n 2p "$FX/urls")" = https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list
  [ "$bad" -eq 0 ] || cat "$FX/urls" "$FX/play.out"
  return "$bad"
}
check "The repository URL names trixie when no release fact is known" repo_url_defaults_to_trixie

# --- join.yml against a stub CLI ---------------------------------------------

# The stub logs every call and answers from the current case's fixtures. It
# succeeds by default; a case opts into failure with $FX/up_fail or
# $FX/status_fail (its content becomes the error text).
mkdir -p "$dir/bin"
cat >"$dir/bin/tailscale" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$FX/calls.log"
case $1 in
  status) [ -e "$FX/status_fail" ] && { cat "$FX/status_fail" >&2; exit 1; }; cat "$FX/status.json" ;;
  debug) [ "$2" = prefs ] || exit 2; cat "$FX/prefs.json" ;;
  up) [ -e "$FX/up_fail" ] && { cat "$FX/up_fail" >&2; exit 1; }; exit 0 ;;
  set) exit 0 ;;
  *) echo "stub: unexpected tailscale $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$dir/bin/tailscale"

key=tskey-auth-fixture
flags='--advertise-routes=192.168.0.0/24 --advertise-tags=tag:subnet-router --accept-dns=false'
set_cmd='set --advertise-routes=192.168.0.0/24 --accept-dns=false'

cat >"$dir/join.yml" <<'YML'
- name: Run the tailscale join against the stub CLI
  hosts: fixture
  gather_facts: false
  tasks:
    - name: Join the tailnet
      ansible.builtin.include_role:
        name: tailscale
        tasks_from: join.yml

    - name: Mark the play as finished
      ansible.builtin.debug:
        msg: join play finished
YML

# node <BackendState> [<AdvertiseRoutes json> <CorpDNS>]   a fresh case's node
node() {
  new_case
  : >"$FX/calls.log"
  printf '{\n\t"Version": "1.90.6",\n\t"BackendState": "%s",\n\t"TailscaleIPs": null\n}\n' "$1" >"$FX/status.json"
  printf '{\n\t"ControlURL": "https://controlplane.tailscale.com",\n\t"RouteAll": false,\n\t"CorpDNS": %s,\n\t"WantRunning": true,\n\t"AdvertiseTags": ["tag:subnet-router"],\n\t"AdvertiseRoutes": %s,\n\t"NoSNAT": false\n}\n' \
    "${3:-false}" "${2:-[\"192.168.0.0/24\"]}" >"$FX/prefs.json"
}

# join [<key>]   runs the fixture play; output to a file, never a pipe
join() {
  local extra=()
  [ $# -gt 0 ] && extra=(-e "tailscale_authkey=$1")
  PATH=$dir/bin:$PATH ansible-playbook -v -i "$dir/inventory" "$dir/join.yml" "${extra[@]}" >"$FX/play.out" 2>&1
}

# calls <verb>   number of stub calls starting with <verb>
calls() { grep -c "^$1\( \|$\)" "$FX/calls.log"; }
recap_changed() { grep -qE "^fixture +: .*changed=$1 " "$FX/play.out"; }
show() { [ "$bad" -eq 0 ] || { echo "--- calls"; cat "$FX/calls.log"; echo "--- play"; cat "$FX/play.out"; }; }

no_key_not_logged_in() {
  node NeedsLogin
  join
  a test $? -ne 0
  a grep -qE 'pre-auth key.*tag:subnet-router|tag:subnet-router.*pre-auth key' "$FX/play.out"
  a test "$(calls 'status --json')" -eq 1
  a test "$(calls up)" -eq 0
  a not_has "$FX/play.out" "join play finished"
  show
  return "$bad"
}
check "Not logged in and no key fails before tailscale up" no_key_not_logged_in

unreadable_state_no_key() {
  local all=0
  node NoState
  join
  a test $? -ne 0
  a test "$(calls up)" -eq 0
  a test "$(calls set)" -eq 0
  a grep -qF 'NoState' "$FX/play.out"
  a grep -qiE 'tailscaled.*(down|unreachable)|(down|unreachable).*tailscaled' "$FX/play.out"
  a not_has "$FX/play.out" "join play finished"
  show
  all=$((all | bad))
  node Running
  echo "failed to connect to local tailscaled" >"$FX/status_fail"
  join
  a test $? -ne 0
  a test "$(calls up)" -eq 0
  a test "$(calls set)" -eq 0
  a test "$(calls 'debug prefs')" -eq 0
  a grep -qiE 'tailscaled.*(down|unreachable)|(down|unreachable).*tailscaled' "$FX/play.out"
  a not_has "$FX/play.out" "join play finished"
  show
  return $((all | bad))
}
check "An unreadable backend state counts as not logged in" unreadable_state_no_key

first_join() {
  node NeedsLogin
  join "$key"
  a test $? -eq 0
  a test "$(calls up)" -eq 1
  a test "$(grep '^up' "$FX/calls.log")" = "up --auth-key=$key $flags"
  a not_has "$FX/play.out" "$key"
  a has "$FX/play.out" "join play finished"
  show
  return "$bad"
}
check "First join advertises the route and tag" first_join

logged_in_untouched() {
  node Running
  join
  a test $? -eq 0
  a test "$(calls 'status --json')" -eq 1
  a test "$(calls 'debug prefs')" -eq 1
  a test "$(calls up)" -eq 0
  a test "$(calls set)" -eq 0
  a recap_changed 0
  a has "$FX/play.out" "join play finished"
  show
  return "$bad"
}
check "A logged-in node is not re-authenticated" logged_in_untouched

stopped_comes_back() {
  node Stopped
  join
  a test $? -eq 0
  a test "$(calls up)" -eq 1
  a test "$(grep '^up' "$FX/calls.log")" = "up $flags"
  a not_has "$FX/calls.log" "--auth-key"
  a has "$FX/play.out" "join play finished"
  show
  return "$bad"
}
check "A stopped node is brought back up without a key" stopped_comes_back

# drift_case <AdvertiseRoutes json> <CorpDNS>
drift_case() {
  node Running "$1" "$2"
  join
  a test $? -eq 0
  a test "$(calls set)" -eq 1
  a test "$(grep '^set' "$FX/calls.log")" = "$set_cmd"
  a test "$(calls up)" -eq 0
  show
}
drift_converges() {
  local all=0
  drift_case '["192.168.0.0/24", "10.0.0.0/24"]' false; all=$((all | bad))
  drift_case null false; all=$((all | bad))
  drift_case '["192.168.0.0/24"]' true; all=$((all | bad))
  return "$all"
}
check "Changed advertise settings converge without re-auth" drift_converges

rejected_key() {
  node NeedsLogin
  echo "backend error: invalid key: API key does not exist" >"$FX/up_fail"
  join "$key"
  a test $? -ne 0
  a test "$(calls up)" -eq 1
  a has "$FX/play.out" "backend error: invalid key: API key does not exist"
  a not_has "$FX/play.out" "$key"
  a not_has "$FX/play.out" "join play finished"
  a grep -qE '^fixture +: .*failed=1 ' "$FX/play.out"
  show
  return "$bad"
}
check "A rejected key fails the play visibly" rejected_key

keeps_snat() {
  local logs=()
  node NeedsLogin; join "$key"; logs+=("$FX/calls.log")
  node Stopped; join; logs+=("$FX/calls.log")
  node Running '["10.0.0.0/24"]' true; join; logs+=("$FX/calls.log")
  a test "$(cat "${logs[@]}" | grep -cE '^(up|set)( |$)')" -eq 3
  a test "$(cat "${logs[@]}" | grep -c -- '--snat-subnet-routes')" -eq 0
  [ "$bad" -eq 0 ] || cat "${logs[@]}"
  return "$bad"
}
check "The router keeps Tailscale's default SNAT" keeps_snat

key_ignored_when_logged_in() {
  node Running
  join "$key"
  a test $? -eq 0
  a test "$(calls 'debug prefs')" -eq 1
  a test "$(calls up)" -eq 0
  a test "$(calls set)" -eq 0
  show
  return "$bad"
}
extra "A key given to a logged-in node is not used" key_ignored_when_logged_in

# --- operator playbook -------------------------------------------------------

operator=ansible/playbooks/01_BASE_CONFIGURATION/tailscale.yml

tun_before_tailscale() {
  python3 - "$operator" <<'PY'
import os, sys, yaml
plays = yaml.safe_load(open(sys.argv[1]))
hv = "ansible/inventory/host_vars/tailscale01"
bad = []
if len(plays) != 2:
    bad.append(f"expected 2 plays, got {len(plays)}")
else:
    tun, ts = plays
    if tun.get("roles") != ["proxmox_lxc_tun"] or tun.get("gather_facts") is not False:
        bad.append(f"play 1 must apply only proxmox_lxc_tun with gather_facts: false: {tun}")
    if ts.get("roles") != ["common", "tailscale"] or ts.get("become") is not True:
        bad.append(f"play 2 must apply common then tailscale with become: true: {ts}")
if (yaml.safe_load(open(f"{hv}/vars.yml")) or {}).get("proxmox_lxc_tun_enabled") is not True:
    bad.append("proxmox_lxc_tun_enabled is not true in host_vars/tailscale01/vars.yml")
if os.path.exists(f"{hv}/vault.yml"):
    bad.append("host_vars/tailscale01/vault.yml exists")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
}
check "TUN passthrough runs before Tailscale" tun_before_tailscale

only_tailscale_group() {
  python3 - "$operator" <<'PY'
import os, sys, yaml
plays = yaml.safe_load(open(sys.argv[1]))
bad = [f"play {p.get('name')!r} targets {p.get('hosts')!r}" for p in plays if p.get("hosts") != "tailscale"]
if not plays:
    bad.append("no plays")
if os.path.exists("ansible/playbooks/02_SERVICES/tailscale.yml"):
    bad.append("ansible/playbooks/02_SERVICES/tailscale.yml exists")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
}
check "The operator playbook targets only the tailscale group" only_tailscale_group

key_prompted_hidden() {
  git ls-files -z ansible/ >"$dir/tracked"
  python3 - "$operator" "$dir/tracked" <<'PY'
import re, sys, yaml
plays = yaml.safe_load(open(sys.argv[1]))
prompts = [v for p in plays for v in p.get("vars_prompt") or [] if v.get("name") == "tailscale_authkey"]
bad = []
if len(prompts) != 1:
    bad.append(f"expected one vars_prompt tailscale_authkey, got {len(prompts)}")
elif prompts[0].get("private") is not True or prompts[0].get("default") != "":
    bad.append(f"tailscale_authkey prompt must be private with an empty default: {prompts[0]}")
assign = re.compile(r"""["']?\btailscale_authkey["']?\s*[:=](?!=)\s*(.*?)\s*$""")
for path in open(sys.argv[2]).read().split("\0"):
    if not path:
        continue
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except (UnicodeDecodeError, IsADirectoryError):
        continue
    for n, line in enumerate(lines, 1):
        if line.lstrip().startswith("#"):
            continue
        m = assign.search(line)
        if m and m.group(1).rstrip("},] ") not in ('""', "''"):
            bad.append(f"{path}:{n}: {line.strip()}")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
}
check "The key is prompted hidden" key_prompted_hidden

exit "$failed"
