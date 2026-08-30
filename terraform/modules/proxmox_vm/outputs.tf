output "vmid" {
  description = "Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "hostname" {
  description = "VM name, matching the Ansible inventory host name."
  value       = var.hostname
}

output "ipv4_address" {
  description = <<-EOT
    Bare IPv4 address without the CIDR suffix, for ansible_host. null on the
    ISO path, where the address is chosen during the manual install.
  EOT
  value       = var.ipv4_address != null ? split("/", var.ipv4_address)[0] : null
}
