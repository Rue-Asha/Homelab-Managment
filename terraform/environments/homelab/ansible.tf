# The Terraform -> Ansible handoff.
#
# These resources hold no infrastructure; they record inventory metadata in
# state, which the cloud.terraform.terraform_provider inventory plugin reads
# back (see ansible/inventory/terraform.yml). One definition of each host, consumed by
# both layers.
#
# The group hierarchy reproduces the old ansible/inventory/hosts exactly -- service
# group -> lxc_container_proxmox / vm_proxmox -> proxmox_guest -- so every
# existing file under ansible/inventory/group_vars/ and ansible/inventory/host_vars/ keeps
# resolving to the same hosts with no edits.

resource "ansible_host" "lxc" {
  for_each = var.lxc_hosts

  name   = each.key
  groups = concat(each.value.groups, ["lxc_container_proxmox", "proxmox_guest"])

  variables = {
    ansible_host = module.lxc[each.key].ipv4_address
    ansible_user = "ansible"
  }
}

resource "ansible_host" "vm" {
  for_each = var.vm_hosts

  name   = each.key
  groups = concat(each.value.groups, ["vm_proxmox", "proxmox_guest"])

  variables = {
    ansible_host = module.vm[each.key].ipv4_address
    ansible_user = "ansible"
  }
}

# The Proxmox node itself is not managed by Terraform -- it is the substrate.
# It still needs to be in the inventory, because ansible/roles/proxmox_lxc_tun delegates
# to it for the raw LXC config the provider cannot express.
resource "ansible_host" "proxmox_node" {
  name   = "proxmox1"
  groups = ["proxmox_node"]

  variables = {
    ansible_host = "192.168.0.22"
    ansible_user = "root"
  }
}
