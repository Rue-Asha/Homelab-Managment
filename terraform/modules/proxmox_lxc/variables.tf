# Identity ---------------------------------------------------------------

variable "hostname" {
  description = "Container hostname; also the Ansible inventory host name."
  type        = string
}

variable "vmid" {
  description = <<-EOT
    Proxmox container ID. Null lets Proxmox assign the next free ID; the
    assigned ID is exported as the `vmid` output. Never derive it from the IP
    address -- the pre-Terraform setup did, which welded the address plan to
    the container ID.
  EOT
  type        = number
  default     = null
}

variable "node_name" {
  description = "Proxmox node the container runs on."
  type        = string
}

# Network ----------------------------------------------------------------

variable "ipv4_address" {
  description = "Static address in CIDR form, e.g. 192.168.0.225/24."
  type        = string

  validation {
    condition     = can(regex("^[0-9.]+/[0-9]+$", var.ipv4_address))
    error_message = "ipv4_address must be in CIDR form, e.g. 192.168.0.225/24."
  }
}

variable "gateway" {
  description = "IPv4 default gateway."
  type        = string
}

variable "bridge" {
  description = "Proxmox bridge to attach the container's eth0 to."
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "Optional VLAN tag for eth0. null leaves the interface untagged."
  type        = number
  default     = null
}

variable "nameservers" {
  description = "DNS resolvers handed to the container."
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# Sizing -----------------------------------------------------------------

variable "cores" {
  description = "CPU cores."
  type        = number
  default     = 1
}

variable "memory" {
  description = "RAM in MiB."
  type        = number
  default     = 1024
}

variable "swap" {
  description = "Swap in MiB."
  type        = number
  default     = 512
}

variable "disk_gb" {
  description = "Root filesystem size in GiB."
  type        = number
  default     = 8
}

variable "datastore_id" {
  description = "Datastore holding the container rootfs."
  type        = string
  default     = "local-lvm"
}

# Image ------------------------------------------------------------------

variable "template_file_id" {
  description = "LXC template volume reference, e.g. local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst."
  type        = string

  validation {
    condition     = can(regex("^[^/][^:]*:vztmpl/.+", var.template_file_id))
    error_message = "template_file_id must be a Proxmox volume reference, not a filesystem path."
  }
}

variable "os_type" {
  description = "Container OS type as Proxmox classifies it."
  type        = string
  default     = "debian"
}

# Access -----------------------------------------------------------------

# No ssh_public_keys variable either: the homelab template already carries the
# ansible user and its keys, and root gets none. See guest-template.
# No root_password variable by design. `pct enter <ctid>` gives passwordless
# root from the node, so a container root password protects nothing while
# still being a secret to store, rotate, and keep out of state. See design D8.

# Behaviour --------------------------------------------------------------

variable "unprivileged" {
  description = "Run the container unprivileged."
  type        = bool
  default     = true
}

variable "start_on_boot" {
  description = "Start the container when the node boots."
  type        = bool
  default     = true
}

variable "started" {
  description = "Desired power state."
  type        = bool
  default     = true
}

variable "features" {
  description = <<-EOT
    Container features. `nesting` defaults to true and should stay that way for
    any systemd guest: without it, systemd-logind fails to start in an
    unprivileged container, and every SSH login then blocks for 25 seconds
    waiting on org.freedesktop.login1 before falling through. Ansible opens a
    connection per task, so that is fatal in practice, not cosmetic.
  EOT
  type = object({
    nesting = optional(bool, true)
    fuse    = optional(bool, false)
    keyctl  = optional(bool, false)
  })
  default = {}
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
