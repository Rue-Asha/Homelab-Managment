# Credentials come from the environment, never from a file in this repo:
#
#   PROXMOX_VE_ENDPOINT    https://192.168.0.22:8006/
#   PROXMOX_VE_API_TOKEN   terraform@pve!<token-id>=<uuid>
#
# They live in ~/.config/homelab/terraform.env (mode 0600, outside the repo)
# and are loaded by direnv via .envrc. This token is the bootstrap credential
# for the whole homelab and stays outside Vault by design -- see design D12.

provider "proxmox" {
  insecure = var.pve_insecure

  # The bpg provider falls back to SSH for the handful of operations the API
  # does not cover. Reuses the same key Ansible already uses for the node.
  ssh {
    agent       = false
    username    = var.pve_ssh_username
    private_key = file(pathexpand(var.pve_ssh_private_key_path))
  }
}

provider "ansible" {}
