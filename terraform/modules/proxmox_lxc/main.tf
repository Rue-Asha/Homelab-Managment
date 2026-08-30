# One container. The fan-out over the host catalogue happens in the root
# module with for_each, so state addresses read as module.lxc["pihole01"] and a
# single host can be targeted or destroyed without disturbing its neighbours.

resource "proxmox_virtual_environment_container" "this" {
  node_name     = var.node_name
  vm_id         = var.vmid
  description   = var.description
  tags          = var.tags
  unprivileged  = var.unprivileged
  start_on_boot = var.start_on_boot
  started       = var.started

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    # Key-only access. Deliberately no `password` -- see variables.tf.
    user_account {
      keys = var.ssh_public_keys
    }
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_gb
  }

  network_interface {
    name    = "eth0"
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = var.os_type
  }

  # Only `nesting` may be set by a non-root PVE user; PVE rejects any change to
  # the other flags with "changing feature flags (except nesting) is only
  # allowed for root@pam". Sending them at all -- even as false -- counts as a
  # change, so they are emitted only when actually requested, and enabling them
  # requires an apply run under root@pam.
  features {
    nesting = var.features.nesting
    fuse    = var.features.fuse ? true : null
    keyctl  = var.features.keyctl ? true : null
  }

  # Deliberately no `prevent_destroy`. It cannot be driven by a variable
  # (lifecycle takes literals only), so it would apply to every host including
  # throwaways, and removing a host from the catalogue would error instead of
  # destroying -- which contradicts the destroy path this migration exists to
  # gain. Protection against an unwanted destroy is reading the plan; that is a
  # mandated gate during import and a habit worth building anyway.
}
