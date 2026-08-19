output "vm_id" {
  value = azurerm_windows_virtual_machine.this.id
}

output "principal_id" {
  value = azurerm_windows_virtual_machine.this.identity[0].principal_id
}

output "private_ip_address" {
  value = var.private_ip_address
}
