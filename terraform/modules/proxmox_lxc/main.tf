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

  # Deliberately no `prevent_destroy` in the lifecycle block below. It cannot be driven by a variable
  # (lifecycle takes literals only), so it would apply to every host including
  # throwaways, and removing a host from the catalogue would error instead of
  # destroying -- which contradicts the destroy path this migration exists to
  # gain. Protection against an unwanted destroy is reading the plan; that is a
  # mandated gate during import and a habit worth building anyway.
  #
  # description is ignored after create because proxmox_lxc_tun's blockinfile
  # markers are comment lines in <ctid>.conf, which PVE reports as part of the
  # description. Without this, plan wants to strip them on every run and the
  # next tailscale playbook run re-inserts them.
  #
  # operating_system is ignored so that bumping the template never plans to
  # replace existing containers; re-image a host with `apply -replace=<addr>`.
  #
  # initialization[0].user_account is ignored because the keys moved into the
  # template; existing containers still carry them in state, and the provider
  # replaces a container when that block disappears from the config.
  lifecycle {
    ignore_changes = [description, operating_system, initialization[0].user_account]
  }
}
