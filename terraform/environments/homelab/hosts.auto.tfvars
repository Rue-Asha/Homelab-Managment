# The host catalogue -- this file replaces inventory/hosts.
#
# vmid and ipv4 are declared independently. The pre-Terraform setup derived the
# container ID from the fourth octet of the address
# (id: "{{ ansible_host.split('.')[-1] | int }}"), which meant a host could not
# be re-addressed without changing its container ID. The existing values are
# carried over unchanged so the import in imports.tf matches the live node.
#
# `groups` are Ansible inventory groups. Every LXC additionally gets
# lxc_container_proxmox and proxmox_guest -- see ansible.tf.

lxc_hosts = {
  "pihole01" = {
    vmid   = 225
    ipv4   = "192.168.0.225/24"
    groups = ["pihole"]
    tags   = ["dns", "terraform"]
    # Sizing was never overridden in host_vars; these are the old
    # roles/proxmox_lxc/defaults/main.yml values, now stated explicitly.
    cores   = 1
    memory  = 1024
    swap    = 512
    disk_gb = 8
  }

  "partygames01" = {
    vmid    = 224
    ipv4    = "192.168.0.224/24"
    groups  = ["partygames"]
    tags    = ["web", "terraform"]
    cores   = 2
    memory  = 1024
    swap    = 512
    disk_gb = 10
  }

  "life-dashboard01" = {
    vmid    = 223
    ipv4    = "192.168.0.223/24"
    groups  = ["life_dashboard"]
    tags    = ["web", "terraform"]
    cores   = 2
    memory  = 1024
    swap    = 512
    disk_gb = 10
  }

  "tailscale01" = {
    vmid    = 230
    ipv4    = "192.168.0.230/24"
    groups  = ["tailscale"]
    tags    = ["vpn", "terraform"]
    cores   = 1
    memory  = 512
    swap    = 512
    disk_gb = 4
    # /dev/net/tun passthrough is NOT declared here. The provider models
    # container config as typed attributes and has no escape hatch for raw
    # lxc.mount.entry lines, so it stays a post-apply Ansible step
    # (roles/proxmox_lxc_tun). See design D6.
  }
}

# retropie01 is deliberately absent: the box is not currently provisioned. Its
# absence is now explicit state rather than a comment in inventory/hosts. When
# it returns, add it here with vm_template_name resolved to a template vmid:
#
# vm_hosts = {
#   retropie01 = {
#     vmid       = 231
#     ipv4       = "192.168.0.231/24"
#     groups     = ["retropie"]
#     clone_vmid = <vmid of debian-12-template>
#     cores      = 4
#     memory     = 4096
#     disk_gb    = 32
#   }
# }
vm_hosts = {}
