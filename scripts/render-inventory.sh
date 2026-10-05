#!/usr/bin/env bash
# Writes ansible/inventory/00-terraform.yml from the `ansible_inventory`
# Terraform output. Reads state only; never contacts the Proxmox API.
#
#   scripts/render-inventory.sh

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

out=ansible/inventory/00-terraform.yml
tmp=$(mktemp)
trap 'command rm -f "$tmp"' EXIT

terraform -chdir=terraform/environments/homelab output -raw ansible_inventory >"$tmp"
[ -s "$tmp" ] || { echo "render-inventory: empty output" >&2; exit 1; }
command mv -f "$tmp" "$out"
chmod 0644 "$out"
echo "rendered $out"
