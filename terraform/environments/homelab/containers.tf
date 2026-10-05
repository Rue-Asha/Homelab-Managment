module "lxc" {
  source = "../../modules/proxmox_lxc"

  # for_each, never count: deleting a host from the catalogue must propose
  # destroying that host only, not renumbering every index after it.
  for_each = var.lxc_hosts

  hostname  = each.key
  vmid      = each.value.vmid
  node_name = var.pve_node_name

  ipv4_address = each.value.ipv4
  gateway      = var.network_gateway
  bridge       = var.network_bridge
  vlan_id      = each.value.vlan_id
  nameservers  = var.network_nameservers

  cores        = each.value.cores
  memory       = each.value.memory
  swap         = each.value.swap
  disk_gb      = each.value.disk_gb
  datastore_id = var.lxc_datastore_id

  template_file_id = coalesce(each.value.template_file_id, var.lxc_template_file_id)

  features = each.value.features
  tags     = each.value.tags
}
