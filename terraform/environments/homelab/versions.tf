terraform {
  # 1.7+ for for_each inside import blocks (see imports.tf).
  required_version = ">= 1.7"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
  }
}
