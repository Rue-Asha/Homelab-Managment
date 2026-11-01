#!/usr/bin/env bash
# Tests for the nginx role's reload wiring, run by proof.sh.

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

# The role's tasks in run order (import_tasks followed), the reload must come after every
# config task and be unconditional: a handler never runs when an earlier run failed after
# writing the config, and the next run then reports every task ok and notifies nothing.
t_reload_in_role() (
  python3 - "${NGINX_ROLE_DIR:-ansible/roles/nginx}" <<'PY'
import os, sys, yaml
rdir = sys.argv[1]
role = rdir + "/tasks/"
def flat(name):
    for t in yaml.safe_load(open(role + name)):
        if "ansible.builtin.import_tasks" in t:
            yield from flat(t["ansible.builtin.import_tasks"])
        else:
            yield t
tasks = list(flat("main.yml"))
cfg = [i for i, t in enumerate(tasks) if "ansible.builtin.template" in t and str(t["ansible.builtin.template"].get("dest", "")).startswith("/etc/nginx/")]
# a key that can skip, swallow or hide the reload makes it as unreliable as the handler was
weak = ("when", "ignore_errors", "failed_when", "tags", "check_mode", "notify", "ignore_unreachable")
rel = [i for i, t in enumerate(tasks)
       if "ansible.builtin.systemd" in t and t["ansible.builtin.systemd"].get("state") == "reloaded"
       and t["ansible.builtin.systemd"].get("name") == "{{ nginx_service_name }}"
       and not any(k in t for k in weak)]
if not cfg:
    sys.exit("no nginx config task found")
if not rel:
    sys.exit("no unconditional reload task in the role: a reload that only runs as a handler is skipped when the play fails first, and never repeated on the rerun")
if rel[-1] < max(cfg):
    sys.exit("reload task runs before the last config task")
for f in os.listdir(role):
    for t in yaml.safe_load(open(role + f)) or []:
        n = t.get("notify")
        if n and "Reload nginx" in ([n] if isinstance(n, str) else n):
            sys.exit(f"{f}: task still notifies Reload nginx")
hf = rdir + "/handlers/main.yml"
if os.path.exists(hf) and any(h.get("name") == "Reload nginx" for h in yaml.safe_load(open(hf)) or []):
    sys.exit("a Reload nginx handler still exists")
PY
)

check "Regression: nginx is reloaded before later roles run" t_reload_in_role

exit "$failed"
