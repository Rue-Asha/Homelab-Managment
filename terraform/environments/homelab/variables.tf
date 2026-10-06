# Node and provider access -----------------------------------------------

variable "pve_node_name" {
  description = "Proxmox node name (the PVE hostname, not the DNS name)."
  type        = string
  default     = "ray"
}

variable "pve_insecure" {
  description = "Skip TLS verification against the PVE API (self-signed certificate)."
  type        = bool
  default     = true
}

variable "pve_node_ip" {
  description = "IP of the Proxmox node, for the Ansible inventory entry."
  type        = string
  default     = "192.168.0.22"
}

variable "pve_node_inventory_name" {
  description = "Ansible inventory host name for the node (kept from the old static inventory)."
  type        = string
  default     = "proxmox1"
}

variable "guest_ansible_user" {
  description = "Unprivileged account Ansible connects as, created by roles/guest_bootstrap."
  type        = string
  default     = "ansible"
}

variable "pve_ssh_enabled" {
  description = "Configure the provider's SSH fallback. False where only the API token is available (the runner)."
  type        = bool
  default     = true
}

variable "pve_ssh_username" {
  description = "SSH user on the Proxmox node, for provider operations the API does not cover."
  type        = string
  default     = "root"
}

variable "pve_ssh_private_key_path" {
  description = "Node key: private key for root@proxmox1, used by the provider SSH fallback and by Ansible for proxmox_node. Opens no guest."
  type        = string
  default     = "~/.ssh/homelab_node_ed25519"
}

# Shared network defaults -------------------------------------------------
# Absorbed from ansible/inventory/group_vars/{lxc_container_proxmox,vm_proxmox}.yml,
# which are deleted once the migration lands.

variable "network_bridge" {
  description = "Default Proxmox bridge for guests."
  type        = string
  default     = "vmbr0"
}

variable "network_gateway" {
  description = "Default IPv4 gateway on the flat LAN."
  type        = string
  default     = "192.168.0.1"
}

variable "network_nameservers" {
  description = "Default DNS resolvers handed to guests."
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# Shared storage and image defaults ---------------------------------------

variable "lxc_datastore_id" {
  description = "Default datastore for container rootfs."
  type        = string
  default     = "local-lvm"
}

variable "lxc_template_file_id" {
  description = "Default LXC template volume reference."
  type        = string
  default     = "local:vztmpl/homelab-debian-13-1.tar.zst"
}

variable "vm_datastore_id" {
  description = "Default datastore for VM disks."
  type        = string
  default     = "local-lvm"
}

# Access ------------------------------------------------------------------

# Host catalogue ----------------------------------------------------------
# Values live in hosts.auto.tfvars. Keyed by hostname and iterated with
# for_each -- never count, which would renumber every host after a deletion
# and propose recreating unrelated containers.

variable "lxc_hosts" {
  description = "LXC containers, keyed by hostname."
  type = map(object({
    # ipv4 is static and hand-set. vmid is left to Proxmox (next free ID); the
    # provider attribute is optional+computed, so unset keeps an existing ID.
    vmid    = optional(number)
    ipv4    = string
    groups  = list(string)
    cores   = optional(number, 1)
    memory  = optional(number, 1024)
    swap    = optional(number, 512)
    disk_gb = optional(number, 8)
    vlan_id = optional(number)
    tags    = optional(list(string), [])
    # Overrides var.lxc_template_file_id for this host.
    template_file_id = optional(string)
    # nesting defaults to true: systemd-logind will not start in an
    # unprivileged container without it, and every SSH login then stalls 25s.
    features = optional(object({
      nesting = optional(bool, true)
      fuse    = optional(bool, false)
      keyctl  = optional(bool, false)
    }), {})
  }))
  default = {}

  # ansible.tf places an LXC only under its groups, so a group-less one is
  # missing from the rendered inventory.
  validation {
    condition     = alltrue([for h in var.lxc_hosts : length(h.groups) > 0])
    error_message = "Every LXC host needs at least one group: a guest without a group is not in the rendered inventory and unreachable for Ansible."
  }
}

variable "vm_hosts" {
  description = "Virtual machines, keyed by hostname."
  type = map(object({
    vmid          = number
    groups        = list(string)
    ipv4          = optional(string)
    clone_vmid    = optional(number)
    cdrom_file_id = optional(string)
    cores         = optional(number, 1)
    sockets       = optional(number, 1)
    memory        = optional(number, 1024)
    disk_gb       = optional(number, 10)
    agent_enabled = optional(bool, true)
    tags          = optional(list(string), [])
  }))
  default = {}
}
