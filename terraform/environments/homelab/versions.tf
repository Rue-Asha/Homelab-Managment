terraform {
  # 1.7+ for for_each inside import blocks (see imports.tf).
  required_version = ">= 1.7"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Local state for now. It is git-ignored and backed up with the control host.
  # Migrating to an S3-compatible backend is `terraform init -migrate-state`
  # away and needs no configuration rewrite -- see design D5.
}
