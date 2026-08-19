locals {
  suffix            = substr(md5("${data.azurerm_client_config.current.subscription_id}-${var.resource_group_name}-${var.name_prefix}-${var.deployment_id}"), 0, 7)
  key_vault         = substr("kv-${var.name_prefix}-${local.suffix}", 0, 24)
  storage_name      = substr(replace("st${var.name_prefix}${local.suffix}", "-", ""), 0, 24)
  deployer_ip_rule  = tonumber(split("/", var.deployer_address_prefix)[1]) == 32 ? split("/", var.deployer_address_prefix)[0] : var.deployer_address_prefix
  workload_subnets  = [var.address_prefixes.management, var.address_prefixes.identity, var.address_prefixes.web, var.address_prefixes.data]
  public_ip_configs = ["web01", "web02", "sql01"]

  vm_definitions = {
    dc01 = {
      fqdn           = "dc01.corp.contoso.local"
      role           = "identity"
      subnet_id      = azurerm_subnet.identity.id
      subnet_name    = azurerm_subnet.identity.name
      private_ip     = "10.50.2.4"
      size           = var.vm_sizes.dc
      image          = var.windows_image
      trusted_launch = true
      os_disk_gb     = 128
      data_disk_gb   = 0
    }
    web01 = {
      fqdn           = "web01.corp.contoso.local"
      role           = "web"
      subnet_id      = azurerm_subnet.web.id
      subnet_name    = azurerm_subnet.web.name
      private_ip     = "10.50.3.4"
      size           = var.vm_sizes.web
      image          = var.windows_image
      trusted_launch = true
      os_disk_gb     = 128
      data_disk_gb   = 0
    }
    web02 = {
      fqdn           = "web02.corp.contoso.local"
      role           = "web"
      subnet_id      = azurerm_subnet.web.id
      subnet_name    = azurerm_subnet.web.name
      private_ip     = "10.50.3.5"
      size           = var.vm_sizes.web
      image          = var.windows_image
      trusted_launch = true
      os_disk_gb     = 128
      data_disk_gb   = 0
    }
    sql01 = {
      fqdn           = "sql01.corp.contoso.local"
      role           = "data"
      subnet_id      = azurerm_subnet.data.id
      subnet_name    = azurerm_subnet.data.name
      private_ip     = "10.50.4.4"
      size           = var.vm_sizes.sql
      image          = var.sql_image
      trusted_launch = false
      os_disk_gb     = 128
      data_disk_gb   = 128
    }
    migrate01 = {
      fqdn           = "migrate01.corp.contoso.local"
      role           = "discovery"
      subnet_id      = azurerm_subnet.management.id
      subnet_name    = azurerm_subnet.management.name
      private_ip     = "10.50.1.4"
      size           = var.vm_sizes.appliance
      image          = var.windows_image
      trusted_launch = true
      os_disk_gb     = 128
      data_disk_gb   = 0
    }
  }

  # Azure Firewall can SNAT outbound flows through any attached public IP, so
  # temporary public deployment access allowlists the deployer plus all three.
  temporary_deployment_public_ip_rules = concat(
    [local.deployer_ip_rule],
    [for name in local.public_ip_configs : azurerm_public_ip.firewall[name].ip_address]
  )
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags = merge(
    var.tags,
    { deploymentId = var.deployment_id },
    var.enable_temporary_deployment_access ? { SecurityControl = "Ignore" } : {}
  )
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.address_prefixes.vnet]
  dns_servers         = ["10.50.2.4"]
  tags                = var.tags
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.address_prefixes.firewall]
}

resource "azurerm_subnet" "management" {
  name                            = "snet-management"
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.address_prefixes.management]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "identity" {
  name                            = "snet-identity"
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.address_prefixes.identity]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "web" {
  name                            = "snet-web"
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.address_prefixes.web]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "data" {
  name                            = "snet-data"
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.address_prefixes.data]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-private-endpoints"
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.address_prefixes.private_endpoints]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_network_security_group" "management" {
  name                = "nsg-management"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_network_security_group" "identity" {
  name                = "nsg-identity"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_network_security_group" "web" {
  name                = "nsg-web"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_network_security_group" "data" {
  name                = "nsg-data"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "domain_services" {
  name                        = "AllowDomainServices"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_ranges     = ["53", "88", "123", "135", "389", "445", "464", "636", "3268-3269", "49152-65535"]
  source_address_prefixes     = [var.address_prefixes.management, var.address_prefixes.web, var.address_prefixes.data]
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.identity.name
}

resource "azurerm_network_security_rule" "winrm_from_management" {
  for_each = {
    identity = azurerm_network_security_group.identity.name
    web      = azurerm_network_security_group.web.name
    data     = azurerm_network_security_group.data.name
  }

  name                        = "AllowWinRmFromManagement"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "5986"
  source_address_prefix       = var.address_prefixes.management
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = each.value
}

resource "azurerm_network_security_rule" "web_internal_http" {
  name                        = "AllowHttpFromIdentity"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443"]
  source_address_prefix       = var.address_prefixes.identity
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.web.name
}

resource "azurerm_network_security_rule" "web_public_http" {
  name                        = "AllowHttpFromFirewallDnat"
  priority                    = 105
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = azurerm_firewall.this.ip_configuration[0].private_ip_address
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.web.name
}

resource "azurerm_network_security_rule" "sql_internal" {
  name                        = "AllowSqlFromWebAndManagement"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefixes     = [var.address_prefixes.web, var.address_prefixes.management]
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.data.name
}

resource "azurerm_network_security_rule" "sql_public" {
  name                        = "AllowSqlFromFirewallDnat"
  priority                    = 105
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = azurerm_firewall.this.ip_configuration[0].private_ip_address
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.data.name
}

resource "azurerm_network_security_rule" "deny_unlisted_vnet" {
  for_each = {
    management = azurerm_network_security_group.management.name
    identity   = azurerm_network_security_group.identity.name
    web        = azurerm_network_security_group.web.name
    data       = azurerm_network_security_group.data.name
  }

  name                        = "DenyUnlistedVnetInbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.address_prefixes.vnet
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = each.value
}

resource "azurerm_subnet_network_security_group_association" "private" {
  for_each = {
    management = { subnet_id = azurerm_subnet.management.id, nsg_id = azurerm_network_security_group.management.id }
    identity   = { subnet_id = azurerm_subnet.identity.id, nsg_id = azurerm_network_security_group.identity.id }
    web        = { subnet_id = azurerm_subnet.web.id, nsg_id = azurerm_network_security_group.web.id }
    data       = { subnet_id = azurerm_subnet.data.id, nsg_id = azurerm_network_security_group.data.id }
  }

  subnet_id                 = each.value.subnet_id
  network_security_group_id = each.value.nsg_id
}

resource "azurerm_public_ip" "firewall" {
  for_each = toset(local.public_ip_configs)

  name                = "pip-${var.name_prefix}-${each.key}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(var.tags, { endpoint = each.key })

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_firewall_policy" "this" {
  name                              = "fwp-${var.name_prefix}"
  resource_group_name               = azurerm_resource_group.this.name
  location                          = azurerm_resource_group.this.location
  sku                               = "Standard"
  threat_intelligence_mode          = "Alert"
  private_ip_ranges                 = [var.address_prefixes.vnet]
  auto_learn_private_ranges_enabled = false
  tags                              = var.tags
}

resource "azurerm_firewall" "this" {
  name                = "afw-${var.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.this.id
  tags                = var.tags

  ip_configuration {
    name                 = "web01"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall["web01"].id
  }

  ip_configuration {
    name                 = "web02"
    public_ip_address_id = azurerm_public_ip.firewall["web02"].id
  }

  ip_configuration {
    name                 = "sql01"
    public_ip_address_id = azurerm_public_ip.firewall["sql01"].id
  }
}

resource "azurerm_route_table" "workloads" {
  name                = "rt-${var.name_prefix}-workloads"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_route" "default_to_firewall" {
  name                   = "default-to-firewall"
  resource_group_name    = azurerm_resource_group.this.name
  route_table_name       = azurerm_route_table.workloads.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

resource "azurerm_subnet_route_table_association" "workloads" {
  for_each = {
    management = azurerm_subnet.management.id
    identity   = azurerm_subnet.identity.id
    web        = azurerm_subnet.web.id
    data       = azurerm_subnet.data.id
  }

  subnet_id      = each.value
  route_table_id = azurerm_route_table.workloads.id
}

resource "azurerm_key_vault" "this" {
  name                          = local.key_vault
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = var.enable_temporary_deployment_access
  tags                          = var.tags

  network_acls {
    bypass         = "None"
    default_action = "Deny"
    ip_rules       = var.enable_temporary_deployment_access ? local.temporary_deployment_public_ip_rules : []
  }
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "key-vault-link"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pep-${local.key_vault}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "key-vault"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

resource "azurerm_storage_account" "staging" {
  name                            = local.storage_name
  location                        = azurerm_resource_group.this.location
  resource_group_name             = azurerm_resource_group.this.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  public_network_access_enabled   = var.enable_temporary_deployment_access
  tags                            = var.tags
}

resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  name                  = "storage-blob-link"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pep-${local.storage_name}-blob"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "storage-blob"
    private_connection_resource_id = azurerm_storage_account.staging.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }
}

resource "azurerm_storage_account_network_rules" "staging" {
  storage_account_id = azurerm_storage_account.staging.id
  default_action     = "Deny"
  bypass             = ["None"]
  ip_rules           = var.enable_temporary_deployment_access ? local.temporary_deployment_public_ip_rules : []

  depends_on = [azurerm_private_endpoint.storage_blob]
}

resource "azurerm_storage_container" "artifacts" {
  name                  = "artifacts"
  storage_account_id    = azurerm_storage_account.staging.id
  container_access_type = "private"
}

module "windows_vm" {
  source   = "./modules/windows-vm"
  for_each = local.vm_definitions

  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  vm_name                = each.key
  role                   = each.value.role
  vm_size                = each.value.size
  admin_username         = var.admin_username
  admin_password         = var.admin_password
  subnet_id              = each.value.subnet_id
  private_ip_address     = each.value.private_ip
  image                  = each.value.image
  trusted_launch         = each.value.trusted_launch
  os_disk_size_gb        = each.value.os_disk_gb
  data_disk_size_gb      = each.value.data_disk_gb
  auto_shutdown_time     = var.auto_shutdown_time
  auto_shutdown_timezone = var.auto_shutdown_timezone
  tags                   = var.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "this" {
  name               = "rcg-${var.name_prefix}"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 500

  nat_rule_collection {
    name     = "public-dnat"
    priority = 100
    action   = "Dnat"

    rule {
      name                = "web01-http"
      protocols           = ["TCP"]
      source_addresses    = [var.deployer_address_prefix]
      destination_address = azurerm_public_ip.firewall["web01"].ip_address
      destination_ports   = ["80"]
      translated_address  = module.windows_vm["web01"].private_ip_address
      translated_port     = "80"
    }

    rule {
      name                = "web02-http"
      protocols           = ["TCP"]
      source_addresses    = [var.deployer_address_prefix]
      destination_address = azurerm_public_ip.firewall["web02"].ip_address
      destination_ports   = ["80"]
      translated_address  = module.windows_vm["web02"].private_ip_address
      translated_port     = "80"
    }

    rule {
      name                = "sql01-dnat"
      protocols           = ["TCP"]
      source_addresses    = [var.deployer_address_prefix]
      destination_address = azurerm_public_ip.firewall["sql01"].ip_address
      destination_ports   = ["1633"]
      translated_address  = module.windows_vm["sql01"].private_ip_address
      translated_port     = "1433"
    }
  }

  network_rule_collection {
    name     = "allow-network-flows"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "identity-dns-recursion"
      protocols             = ["TCP", "UDP"]
      source_addresses      = [var.address_prefixes.identity]
      destination_addresses = ["*"]
      destination_ports     = ["53"]
    }

    rule {
      name                  = "domain-services"
      protocols             = ["TCP", "UDP"]
      source_addresses      = [var.address_prefixes.management, var.address_prefixes.web, var.address_prefixes.data]
      destination_addresses = [local.vm_definitions.dc01.private_ip]
      destination_ports     = ["53", "88", "123", "135", "389", "445", "464", "636", "3268-3269", "49152-65535"]
    }

    rule {
      name                  = "migrate-winrm"
      protocols             = ["TCP"]
      source_addresses      = [var.address_prefixes.management]
      destination_addresses = [local.vm_definitions.dc01.private_ip, local.vm_definitions.web01.private_ip, local.vm_definitions.web02.private_ip, local.vm_definitions.sql01.private_ip]
      destination_ports     = ["5986"]
    }

    rule {
      name                  = "migrate-sql"
      protocols             = ["TCP"]
      source_addresses      = [var.address_prefixes.management]
      destination_addresses = [local.vm_definitions.sql01.private_ip]
      destination_ports     = ["1433"]
    }

    rule {
      name                  = "web-to-sql"
      protocols             = ["TCP"]
      source_addresses      = [var.address_prefixes.web]
      destination_addresses = [local.vm_definitions.sql01.private_ip]
      destination_ports     = ["1433"]
    }

    rule {
      name                  = "dc-to-web"
      protocols             = ["TCP"]
      source_addresses      = [var.address_prefixes.identity]
      destination_addresses = [local.vm_definitions.web01.private_ip, local.vm_definitions.web02.private_ip]
      destination_ports     = ["80", "443"]
    }
  }

  application_rule_collection {
    name     = "allow-bootstrap-https"
    priority = 300
    action   = "Allow"

    rule {
      name             = "bootstrap-and-platform"
      source_addresses = local.workload_subnets
      destination_fqdns = [
        "aka.ms",
        "go.microsoft.com",
        "download.microsoft.com",
        "packages.microsoft.com",
        "management.azure.com",
        "login.microsoftonline.com",
        "login.windows.net",
        "*.microsoft.com",
        "*.microsoftonline.com",
        "*.windowsupdate.com",
        "*.update.microsoft.com",
        "*.delivery.mp.microsoft.com",
        "*.do.dsp.mp.microsoft.com",
        "*.blob.core.windows.net",
        "*.vault.azure.net",
        "*.vaultcore.azure.net",
        "dc.services.visualstudio.com"
      ]

      protocols {
        type = "Http"
        port = 80
      }

      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name             = "azure-migrate"
      source_addresses = [var.address_prefixes.management]
      destination_fqdns = [
        "*.servicebus.windows.net",
        "*.azurewebsites.net",
        "*.migration.windowsazure.com",
        "*.sitecatalyst.omniture.com"
      ]

      protocols {
        type = "Https"
        port = 443
      }
    }
  }
}
