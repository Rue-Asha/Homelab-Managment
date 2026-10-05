locals {
  # VMs are not on the template: cloud-init still seeds the ansible user.
  vm_ssh_public_keys = [
    for k in ["guest_ed25519.pub", "deploy_ed25519.pub"] :
    trimspace(file("${path.module}/../../../ansible/keys/${k}"))
  ]
}

module "vm" {
  source = "../../modules/proxmox_vm"

  for_each = var.vm_hosts

  hostname  = each.key
  vmid      = each.value.vmid
  node_name = var.pve_node_name

  clone_vmid    = each.value.clone_vmid
  cdrom_file_id = each.value.cdrom_file_id

  ipv4_address = each.value.ipv4
  gateway      = var.network_gateway
  bridge       = var.network_bridge
  nameservers  = var.network_nameservers

  cores        = each.value.cores
  sockets      = each.value.sockets
  memory       = each.value.memory
  disk_gb      = each.value.disk_gb
  datastore_id = var.vm_datastore_id

  ssh_public_keys = local.vm_ssh_public_keys
  agent_enabled   = each.value.agent_enabled
  tags            = each.value.tags
}
