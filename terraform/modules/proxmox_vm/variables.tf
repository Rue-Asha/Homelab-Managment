# Covers both former provisioning paths in one module:
#   - clone from a Proxmox template + cloud-init  (was ansible/roles/proxmox_vm_template)
#   - bare shell with an ISO attached, installed by hand at the console
#     (was ansible/roles/proxmox_vm_iso)
# Set exactly one of `clone_vmid` or `cdrom_file_id`.

variable "hostname" {
  description = "VM name; also the Ansible inventory host name."
  type        = string
}

variable "vmid" {
  description = "Proxmox VM ID, declared independently of the IP address."
  type        = number
}

variable "node_name" {
  description = "Proxmox node the VM runs on."
  type        = string
}

# Source -----------------------------------------------------------------

variable "clone_vmid" {
  description = "Template VM ID to clone from. Mutually exclusive with cdrom_file_id."
  type        = number
  default     = null
}

variable "clone_full" {
  description = "Full clone rather than linked clone."
  type        = bool
  default     = true
}

variable "cdrom_file_id" {
  description = <<-EOT
    ISO volume reference, e.g. local:iso/debian-13.4.0-amd64-netinst.iso.
    Produces a VM shell that a human installs at the console; Ansible takes
    over afterwards. Mutually exclusive with clone_vmid.
  EOT
  type        = string
  default     = null
}

# Sizing -----------------------------------------------------------------

variable "cores" {
  description = "CPU cores per socket."
  type        = number
  default     = 1
}

variable "sockets" {
  description = "CPU sockets."
  type        = number
  default     = 1
}

variable "memory" {
  description = "RAM in MiB."
  type        = number
  default     = 1024
}

variable "disk_gb" {
  description = "Primary disk size in GiB."
  type        = number
  default     = 10
}

variable "datastore_id" {
  description = "Datastore holding the VM disk."
  type        = string
  default     = "local-lvm"
}

# Network ----------------------------------------------------------------

variable "bridge" {
  description = "Proxmox bridge to attach the VM's first NIC to."
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "Optional VLAN tag. null leaves the interface untagged."
  type        = number
  default     = null
}

variable "ipv4_address" {
  description = "Static address in CIDR form for cloud-init. Ignored on the ISO path."
  type        = string
  default     = null
}

variable "gateway" {
  description = "IPv4 default gateway for cloud-init."
  type        = string
  default     = null
}

variable "nameservers" {
  description = "DNS resolvers handed to cloud-init."
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# Access -----------------------------------------------------------------

# No cloud-init password by design -- see proxmox_lxc/variables.tf and design D8.

variable "ci_user" {
  description = "cloud-init user created on first boot."
  type        = string
  default     = "ansible"
}

variable "ssh_public_keys" {
  description = "Public keys seeded via cloud-init."
  type        = list(string)
  default     = []
}

variable "ci_datastore_id" {
  description = "Datastore holding the cloud-init drive."
  type        = string
  default     = "local-lvm"
}

# Behaviour --------------------------------------------------------------

variable "agent_enabled" {
  description = "Expect the QEMU guest agent. Leave false on the ISO path until the OS is installed."
  type        = bool
  default     = true
}

variable "started" {
  description = "Desired power state."
  type        = bool
  default     = true
}

variable "start_on_boot" {
  description = "Start the VM when the node boots."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Proxmox tags for UI grouping."
  type        = list(string)
  default     = []
}

variable "description" {
  description = "Free-text note shown in the Proxmox UI."
  type        = string
  default     = "Managed by Terraform"
}
