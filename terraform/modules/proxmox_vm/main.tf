locals {
  is_clone = var.clone_vmid != null
}

# Guard the mutually-exclusive source paths at plan time rather than letting
# the provider fail halfway through an apply.
resource "terraform_data" "source_check" {
  lifecycle {
    precondition {
      condition     = (var.clone_vmid != null) != (var.cdrom_file_id != null)
      error_message = "Set exactly one of clone_vmid or cdrom_file_id."
    }

    precondition {
      condition     = !local.is_clone || var.ipv4_address != null
      error_message = "The clone path uses cloud-init and requires ipv4_address."
    }
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  depends_on = [terraform_data.source_check]

  node_name     = var.node_name
  vm_id         = var.vmid
  name          = var.hostname
  description   = var.description
  tags          = var.tags
  started       = var.started
  on_boot       = var.start_on_boot
  scsi_hardware = "virtio-scsi-single"

  agent {
    enabled = var.agent_enabled
  }

  cpu {
    cores   = var.cores
    sockets = var.sockets
    type    = "host"
  }

  memory {
    dedicated = var.memory
  }

  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  # --- clone path: template + cloud-init -------------------------------
  dynamic "clone" {
    for_each = local.is_clone ? [1] : []
    content {
      vm_id = var.clone_vmid
      full  = var.clone_full
    }
  }

  dynamic "initialization" {
    for_each = local.is_clone ? [1] : []
    content {
      datastore_id = var.ci_datastore_id

      ip_config {
        ipv4 {
          address = var.ipv4_address
          gateway = var.gateway
        }
      }

      dns {
        servers = var.nameservers
      }

      # Key-only. No `password` -- see variables.tf.
      user_account {
        username = var.ci_user
        keys     = var.ssh_public_keys
      }
    }
  }

  # --- ISO path: bare shell, installed by hand at the console ----------
  dynamic "cdrom" {
    for_each = var.cdrom_file_id != null ? [1] : []
    content {
      file_id = var.cdrom_file_id
    }
  }

  dynamic "disk" {
    for_each = var.cdrom_file_id != null ? [1] : []
    content {
      datastore_id = var.datastore_id
      interface    = "scsi0"
      size         = var.disk_gb
    }
  }
}
