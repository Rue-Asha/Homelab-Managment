#!/usr/bin/env bash
# Pulls the inventory runner01 rendered after its last apply or deploy and
# writes it to ansible/inventory/00-terraform.yml. Terraform state lives only on
# the runner, so the workstation has no way to render it itself.
#
#   scripts/fetch-inventory.sh
#
# Env: RUNNER_HOST (default 192.168.0.224), RUNNER_KEY (default the guest key).

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

host=${RUNNER_HOST:-192.168.0.224}
key=${RUNNER_KEY:-$HOME/.ssh/homelab_guest_ed25519}
out=ansible/inventory/00-terraform.yml
tmp=$(mktemp)
trap 'command rm -f "$tmp"' EXIT

ssh -i "$key" -o IdentitiesOnly=yes "ansible@$host" \
  sudo cat /home/github-runner/.cache/homelab/00-terraform.yml >"$tmp"
[ -s "$tmp" ] || { echo "fetch-inventory: empty file from $host" >&2; exit 1; }
command mv -f "$tmp" "$out"
chmod 0644 "$out"
echo "fetched $out"
