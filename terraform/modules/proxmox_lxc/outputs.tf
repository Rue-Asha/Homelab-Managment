output "vmid" {
  description = "Proxmox container ID."
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "hostname" {
  description = "Container hostname, matching the Ansible inventory host name."
  value       = var.hostname
}

output "ipv4_address" {
  description = "Bare IPv4 address without the CIDR suffix, for ansible_host."
  value       = split("/", var.ipv4_address)[0]
}

output "ipv4_cidr" {
  description = "IPv4 address in CIDR form, as configured on the interface."
  value       = var.ipv4_address
}
