output "scenario" {
  value = local.scenario
}

output "azureVmRoles" {
  value = local.azure_vm_roles
}

output "subnets" {
  value = local.subnets
}

output "hostVmName" {
  value = local.host_vm_name
}

output "hostPrivateAddress" {
  value = azurerm_network_interface.host.ip_configuration[0].private_ip_address
}
