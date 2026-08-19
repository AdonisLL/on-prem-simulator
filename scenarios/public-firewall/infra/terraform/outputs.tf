output "resource_group_id" {
  value = azurerm_resource_group.this.id
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "firewall_id" {
  value = azurerm_firewall.this.id
}

output "firewall_private_ip_address" {
  value = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

output "firewall_public_ip_addresses" {
  value = {
    web01 = azurerm_public_ip.firewall["web01"].ip_address
    web02 = azurerm_public_ip.firewall["web02"].ip_address
    sql01 = azurerm_public_ip.firewall["sql01"].ip_address
  }
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "staging_storage_account_name" {
  value = azurerm_storage_account.staging.name
}

output "public_endpoints" {
  value = {
    web01 = {
      address = azurerm_public_ip.firewall["web01"].ip_address
      port    = 80
      url     = "http://${azurerm_public_ip.firewall["web01"].ip_address}"
    }
    web02 = {
      address = azurerm_public_ip.firewall["web02"].ip_address
      port    = 80
      url     = "http://${azurerm_public_ip.firewall["web02"].ip_address}"
    }
    sql01 = {
      address = azurerm_public_ip.firewall["sql01"].ip_address
      port    = 1633
    }
  }
}

output "discovery_inventory" {
  value = [
    { fqdn = "dc01.corp.contoso.local", ip_address = "10.50.2.4", operating_system = "Windows Server" },
    { fqdn = "web01.corp.contoso.local", ip_address = "10.50.3.4", operating_system = "Windows Server" },
    { fqdn = "web02.corp.contoso.local", ip_address = "10.50.3.5", operating_system = "Windows Server" },
    { fqdn = "sql01.corp.contoso.local", ip_address = "10.50.4.4", operating_system = "Windows Server" }
  ]
}

output "workload_inventory" {
  value = [
    {
      name               = "dc01"
      fqdn               = "dc01.corp.contoso.local"
      role               = "identity"
      private_ip_address = "10.50.2.4"
      subnet             = azurerm_subnet.identity.name
      public_endpoint    = null
    },
    {
      name               = "migrate01"
      fqdn               = "migrate01.corp.contoso.local"
      role               = "discovery"
      private_ip_address = "10.50.1.4"
      subnet             = azurerm_subnet.management.name
      public_endpoint    = null
    },
    {
      name               = "sql01"
      fqdn               = "sql01.corp.contoso.local"
      role               = "data"
      private_ip_address = "10.50.4.4"
      subnet             = azurerm_subnet.data.name
      public_endpoint    = "${azurerm_public_ip.firewall["sql01"].ip_address}:1633"
    },
    {
      name               = "web01"
      fqdn               = "web01.corp.contoso.local"
      role               = "web"
      private_ip_address = "10.50.3.4"
      subnet             = azurerm_subnet.web.name
      public_endpoint    = "http://${azurerm_public_ip.firewall["web01"].ip_address}"
    },
    {
      name               = "web02"
      fqdn               = "web02.corp.contoso.local"
      role               = "web"
      private_ip_address = "10.50.3.5"
      subnet             = azurerm_subnet.web.name
      public_endpoint    = "http://${azurerm_public_ip.firewall["web02"].ip_address}"
    }
  ]
}

output "web_urls" {
  value = [
    "http://${azurerm_public_ip.firewall["web01"].ip_address}",
    "http://${azurerm_public_ip.firewall["web02"].ip_address}"
  ]
}
