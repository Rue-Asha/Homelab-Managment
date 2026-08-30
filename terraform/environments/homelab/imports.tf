# Adoption of the four already-running containers.
#
# These are live services with persistent data (life-dashboard01 holds a SQLite
# file, pihole01 holds DNS config). They are imported, never rebuilt.
#
# The gate is a COMPLETELY EMPTY `terraform plan` after import. If the plan
# proposes any change, the configuration is wrong and gets corrected -- the
# container is never modified to match the config. Any proposed destroy or
# replace of a running container is a hard stop.
#
# This file stays in the repo after the migration. If state is ever lost,
# re-adoption is one `terraform apply` away rather than archaeology.
#
# Import ID format for bpg/proxmox containers is <node_name>/<vm_id>.
# VERIFY against the pinned provider version's docs before the first run:
#   https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_container

import {
  for_each = var.lxc_hosts

  to = module.lxc[each.key].proxmox_virtual_environment_container.this
  id = "${var.pve_node_name}/${each.value.vmid}"
}

# Once every container in the catalogue has been imported and `terraform plan`
# reports no changes, new hosts added to hosts.auto.tfvars would also be matched
# by the for_each above and fail to import (they do not exist yet). At that
# point, replace the block above with an explicit list of the adopted hosts:
#
#   import {
#     for_each = toset(["pihole01", "partygames01", "life-dashboard01", "tailscale01"])
#     to       = module.lxc[each.key].proxmox_virtual_environment_container.this
#     id       = "${var.pve_node_name}/${var.lxc_hosts[each.key].vmid}"
#   }
#
# Terraform ignores import blocks for resources already in state, so leaving the
# narrowed list in place is harmless and keeps the recovery path documented.
