# The Terraform -> Ansible handoff.
#
# Terraform renders the Ansible inventory directly. The alternative -- the
# `ansible/ansible` provider plus the cloud.terraform inventory plugin -- was
# the original design (D7) and is not usable here: cloud.terraform 4.0.0, its
# latest release, calls `get_bin_path(..., required=True)`, and ansible-core
# 2.21 removed that argument. The plugin fails to parse the inventory outright.
#
# The inventory is an output of this configuration, written to disk by
# scripts/render-inventory.sh from remote state. It is not committed: applying on
# the runner would otherwise need a push to main, which re-triggers the deploy.

locals {
  # Service groups, derived from the host catalogue.
  lxc_groups = distinct(flatten([for h in var.lxc_hosts : h.groups]))
  vm_groups  = distinct(flatten([for h in var.vm_hosts : h.groups]))

  # Reproduces the pre-Terraform group hierarchy exactly:
  #   <service> -> lxc_container_proxmox | vm_proxmox -> proxmox_guest
  # so every existing file under inventory/group_vars and inventory/host_vars
  # keeps resolving to the same hosts with no edits.
  ansible_inventory = {
    all = {
      children = {
        proxmox_node = {
          hosts = {
            (var.pve_node_inventory_name) = {
              ansible_host                 = var.pve_node_ip
              ansible_user                 = var.pve_ssh_username
              ansible_ssh_private_key_file = var.pve_ssh_private_key_path
            }
          }
        }

        proxmox_guest = {
          children = {
            lxc_container_proxmox = {
              children = {
                for g in local.lxc_groups : g => {
                  hosts = {
                    for name, cfg in var.lxc_hosts : name => {
                      ansible_host = module.lxc[name].ipv4_address
                      ansible_user = var.guest_ansible_user
                      # Consumed by roles/proxmox_lxc_tun, which edits
                      # /etc/pve/lxc/<ctid>.conf on the node. Terraform is the
                      # source of truth for the container ID; this replaces the
                      # old `id: {{ ansible_host.split('.')[-1] }}` derivation
                      # that welded the address plan to container IDs.
                      lxc_ctid = module.lxc[name].vmid
                    } if contains(cfg.groups, g)
                  }
                }
              }
            }

            vm_proxmox = {
              children = {
                for g in local.vm_groups : g => {
                  hosts = {
                    for name, cfg in var.vm_hosts : name => {
                      ansible_host = module.vm[name].ipv4_address
                      ansible_user = var.guest_ansible_user
                    } if contains(cfg.groups, g)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

# Rendered to ansible/inventory/00-terraform.yml by scripts/render-inventory.sh
# from this output, so applying on the runner needs no commit to main.
# yamlencode rather than a template: the nesting is generated, and hand-rolled
# indentation in a heredoc is exactly where this would break silently.
output "ansible_inventory" {
  description = "Ansible inventory, rendered by scripts/render-inventory.sh."
  value       = <<-EOT
    ---
    # GENERATED FROM TERRAFORM STATE -- DO NOT EDIT.
    # Source of truth: terraform/environments/homelab/hosts.auto.tfvars
    # Regenerate with: scripts/render-inventory.sh
    ${yamlencode(local.ansible_inventory)}
  EOT
}
