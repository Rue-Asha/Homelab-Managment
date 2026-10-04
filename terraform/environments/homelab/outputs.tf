output "lxc_hosts" {
  description   =   "Hostname -> vmid and address, for operator inspection and for diffing against the old static inventory."
  value = {
    for name, m in module.lxc : name => {
      vmid = m.vmid
      ipv4 = m.ipv4_address
    }
  }
}

output "vm_hosts" {
  description = "Hostname -> vmid and address for managed VMs."
  value = {
    for name, m in module.vm : name => {
      vmid = m.vmid
      ipv4 = m.ipv4_address
    }
  }
}
