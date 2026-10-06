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
  # 223 / .223 are reused from the retired life-dashboard01.
  "life-manager01" = {
    vmid    = 223
    ipv4    = "192.168.0.223/24"
    groups  = ["life_manager"]
    tags    = ["web", "terraform"]
    cores   = 2
    memory  = 1024
    swap    = 512
    disk_gb = 10
  }

  # Self-hosted GitHub Actions runner for the deploy workflow. Configured by
  # 01_BASE_CONFIGURATION/deploy_runner.yml, never by a deploy. Debian 13
  # because the ansible-core pinned in ci/requirements.txt needs Python 3.12+.
  "runner01" = {
    vmid    = 224
    ipv4    = "192.168.0.224/24"
    groups  = ["github_runner"]
    tags    = ["ci", "terraform"]
    cores   = 2
    memory  = 2048
    swap    = 512
    disk_gb = 12
  }

  # Shared check host, one runner per repo in `check_runner_repos`. Holds no
  # credentials and reaches nothing but the internet. Configured by
  # 01_BASE_CONFIGURATION/check_runner.yml, never by a deploy.
  "check01" = {
    vmid    = 226
    ipv4    = "192.168.0.226/24"
    groups  = ["check_runner"]
    tags    = ["ci", "terraform"]
    cores   = 4
    memory  = 16384
    swap    = 512
    disk_gb = 32
  }

  # Retired in efa9f49 and brought back with the same identity, so the router
  # needs no new address. Configured by 02_SERVICES/pihole.yml.
  "pihole01" = {
    vmid    = 225
    ipv4    = "192.168.0.225/24"
    groups  = ["pihole"]
    tags    = ["dns", "terraform"]
    cores   = 1
    memory  = 512
    swap    = 512
    disk_gb = 4
  }

  # Light SSR + node:sqlite, no game servers or long-lived connections; the
  # games run client-side. Configured by 02_SERVICES/rues-arcade.yml.
  "rues-arcade01" = {
    vmid    = 227
    ipv4    = "192.168.0.227/24"
    groups  = ["rues_arcade"]
    tags    = ["web", "terraform"]
    cores   = 1
    memory  = 768
    swap    = 512
    disk_gb = 6
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
#     clone_vmid = 1001   # debian-12-template (1000 = debian-13-template)
#     cores      = 4
#     memory     = 4096
#     disk_gb    = 32
#   }
# }
vm_hosts = {}
