#!/usr/bin/env bash
# Copies runner01's Terraform state to the workstation as a timestamped backup.
# The state lives only on the runner (design D7), so this is the only copy that
# survives a lost runner. It is a backup, never a working state: nothing here
# reads or writes it back.
#
#   scripts/fetch-state.sh
#
# Env: RUNNER_HOST (default 192.168.0.224), RUNNER_KEY (default the guest key),
#      STATE_BACKUP_DIR (default ~/.local/state/homelab/backups).

set -euo pipefail

host=${RUNNER_HOST:-192.168.0.224}
key=${RUNNER_KEY:-$HOME/.ssh/homelab_guest_ed25519}
dir=${STATE_BACKUP_DIR:-$HOME/.local/state/homelab/backups}
out=$dir/terraform.tfstate.$(date +%Y%m%dT%H%M%S)
tmp=$(mktemp)
trap 'command rm -f "$tmp"' EXIT

mkdir -p "$dir"
chmod 0700 "$dir"

ssh -i "$key" -o IdentitiesOnly=yes "ansible@$host" \
  sudo cat /home/github-runner/.local/state/homelab/terraform.tfstate >"$tmp"
[ -s "$tmp" ] || { echo "fetch-state: empty file from $host" >&2; exit 1; }
jq -e .serial "$tmp" >/dev/null || { echo "fetch-state: not a state file" >&2; exit 1; }
command mv -f "$tmp" "$out"
chmod 0600 "$out"
echo "saved $out"
