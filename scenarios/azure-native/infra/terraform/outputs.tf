output "resource_group_id" {
  value = azurerm_resource_group.this.id
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "bastion_id" {
  value = try(azurerm_bastion_host.this[0].id, null)
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "staging_storage_account_name" {
  value = azurerm_storage_account.staging.name
}

output "discovery_inventory" {
  value = [
    { fqdn = "dc01.corp.contoso.local", ip_address = "10.50.2.4", operating_system = "Windows Server" },
    { fqdn = "web01.corp.contoso.local", ip_address = "10.50.3.4", operating_system = "Windows Server" },
    { fqdn = "web02.corp.contoso.local", ip_address = "10.50.3.5", operating_system = "Windows Server" },
    { fqdn = "sql01.corp.contoso.local", ip_address = "10.50.4.4", operating_system = "Windows Server" }
  ]
}

output "web_urls" {
  value = [
    "http://web01.corp.contoso.local",
    "http://web02.corp.contoso.local"
  ]
}
