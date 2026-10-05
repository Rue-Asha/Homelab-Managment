#!/usr/bin/env bash
# Writes ansible/inventory/00-terraform.yml from the `ansible_inventory`
# Terraform output. Reads state only; never contacts the Proxmox API.
#
#   scripts/render-inventory.sh

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

out=ansible/inventory/00-terraform.yml
tmp=$(mktemp)
err=$(mktemp)
cache=$HOME/.cache/homelab/00-terraform.yml
trap 'command rm -f "$tmp" "$err"' EXIT

if ! terraform -chdir=terraform/environments/homelab output -raw ansible_inventory >"$tmp" 2>"$err"; then
  if grep -q 'Output "ansible_inventory" not found' "$err" && [ -s "$cache" ]; then
    command cp -f "$cache" "$tmp"
    echo "render-inventory: ansible_inventory output not in state; using cached $cache" >&2
  else
    cat "$err" >&2
    echo "render-inventory: failed to read ansible_inventory output" >&2
    exit 1
  fi
fi
[ -s "$tmp" ] || { echo "render-inventory: empty output" >&2; exit 1; }
command mv -f "$tmp" "$out"
chmod 0644 "$out"
echo "rendered $out"
