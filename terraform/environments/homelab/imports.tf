# No active import blocks.
#
# The original plan adopted the four pre-existing containers into state with
# `import`. That was dropped: the operator chose to rebuild the guests from
# scratch instead, which proves the create path end to end and leaves the
# containers genuinely matching the declaration rather than merely close enough
# to produce an empty plan. See design D9.
#
# An active import block for a resource that does not exist makes `terraform
# plan` fail, so this cannot be left enabled. It is kept as a template because
# the recovery argument still holds once the guests exist: if state is ever
# lost, uncomment this and Terraform re-adopts the running containers instead
# of proposing to recreate them.
#
# Import ID format for bpg/proxmox containers is <node_name>/<vm_id>. LXC hosts
# no longer declare a vmid, so at recovery time write each container's real ID
# into the id by hand (from `pct list` on the node or the Proxmox UI), e.g. with
# a local map keyed by hostname. Skipping the import makes apply create new
# containers with new IDs next to the old ones, on the same static IPs.
#
# import {
#   for_each = var.lxc_hosts
#
#   to = module.lxc[each.key].proxmox_virtual_environment_container.this
#   id = "${var.pve_node_name}/${each.value.vmid}"
# }
