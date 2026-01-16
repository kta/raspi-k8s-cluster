output "vm_id" {
  description = "VM ID"
  value       = proxmox_virtual_environment_vm.vm.id
}

output "vm_name" {
  description = "VM 名"
  value       = proxmox_virtual_environment_vm.vm.name
}

output "ip_address" {
  description = "VM IP アドレス"
  value       = var.ip_address
}

output "node_name" {
  description = "配置先ノード"
  value       = var.node_name
}
