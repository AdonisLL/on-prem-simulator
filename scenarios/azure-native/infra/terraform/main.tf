locals {
  suffix       = substr(md5("${data.azurerm_client_config.current.subscription_id}-${var.resource_group_name}-${var.name_prefix}-${var.deployment_id}"), 0, 7)
  key_vault    = substr("kv-${var.name_prefix}-${local.suffix}", 0, 24)
  storage_name = substr(replace("st${var.name_prefix}${local.suffix}", "-", ""), 0, 24)
  vm_definitions = {
    dc01 = {
      role           = "identity"
      subnet_id      = azurerm_subnet.identity.id
      private_ip     = "10.50.2.4"
      size           = var.vm_sizes.dc
      image          = var.windows_image
      trusted_launch = true
      os_disk_gb     = 128
      data_disk_gb   = 0
    }
    web01 = {
      role           = "web"
      subnet_id      = azurerm_subnet.web.id
      private_ip     = "10.50.3.4"
      size           = var.vm_sizes.web
      image          = var.windows_image
      trusted_launch = true
      os_disk_gb     = 128
      data_disk_gb   = 0
    }
    web02 = {
      role           = "web"
      subnet_id      = azurerm_subnet.web.id
      private_ip     = "10.50.3.5"
      size           = var.vm_sizes.web
      image          = var.windows_image
      trusted_launch = true
      os_disk_gb     = 128
      data_disk_gb   = 0
    }
    sql01 = {
      role           = "data"
      subnet_id      = azurerm_subnet.data.id
      private_ip     = "10.50.4.4"
      size           = var.vm_sizes.sql
      image          = var.sql_image
      trusted_launch = false
      os_disk_gb     = 128
      data_disk_gb   = 128
    }
    migrate01 = {
      role           = "discovery"
      subnet_id      = azurerm_subnet.management.id
      private_ip     = "10.50.1.4"
      size           = var.vm_sizes.appliance
      image          = var.windows_image
      trusted_launch = true
      os_disk_gb     = 128
      data_disk_gb   = 0
    }
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = merge(var.tags, { deploymentId = var.deployment_id })
}

resource "azurerm_public_ip" "nat" {
  name                = "pip-${var.name_prefix}-nat"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "ng-${var.name_prefix}"
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.address_prefixes.vnet]
  dns_servers         = ["10.50.2.4"]
  tags                = var.tags
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.address_prefixes.bastion]
}

resource "azurerm_subnet" "management" {
  name                              = "snet-management"
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.address_prefixes.management]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"
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

resource "azurerm_subnet_nat_gateway_association" "private" {
  for_each = {
    management = azurerm_subnet.management.id
    identity   = azurerm_subnet.identity.id
    web        = azurerm_subnet.web.id
    data       = azurerm_subnet.data.id
  }
  subnet_id      = each.value
  nat_gateway_id = azurerm_nat_gateway.this.id
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

resource "azurerm_network_security_rule" "rdp" {
  for_each = {
    management = azurerm_network_security_group.management.name
    identity   = azurerm_network_security_group.identity.name
    web        = azurerm_network_security_group.web.name
    data       = azurerm_network_security_group.data.name
  }
  name                        = "AllowRdpFromBastion"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = var.address_prefixes.bastion
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = each.value
}

resource "azurerm_network_security_rule" "winrm" {
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
  source_address_prefixes     = [var.address_prefixes.management, var.address_prefixes.identity]
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = each.value
}

resource "azurerm_network_security_rule" "domain_services" {
  name                        = "AllowDomainServices"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_ranges     = ["53", "88", "123", "135", "389", "445", "464", "636", "3268-3269", "49152-65535"]
  source_address_prefix       = var.address_prefixes.vnet
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.identity.name
}

resource "azurerm_network_security_rule" "web_http" {
  name                        = "AllowHttpFromIdentity"
  priority                    = 120
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

resource "azurerm_network_security_rule" "sql" {
  name                        = "AllowSqlFromWebAndManagement"
  priority                    = 120
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
    management = { subnet = azurerm_subnet.management.id, nsg = azurerm_network_security_group.management.id }
    identity   = { subnet = azurerm_subnet.identity.id, nsg = azurerm_network_security_group.identity.id }
    web        = { subnet = azurerm_subnet.web.id, nsg = azurerm_network_security_group.web.id }
    data       = { subnet = azurerm_subnet.data.id, nsg = azurerm_network_security_group.data.id }
  }
  subnet_id                 = each.value.subnet
  network_security_group_id = each.value.nsg
}

resource "azurerm_public_ip" "bastion" {
  count               = var.enable_bastion ? 1 : 0
  name                = "pip-${var.name_prefix}-bastion"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "this" {
  count               = var.enable_bastion ? 1 : 0
  name                = "bas-${var.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Basic"
  tags                = var.tags

  ip_configuration {
    name                 = "default"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
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
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
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
  subnet_id           = azurerm_subnet.management.id
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
  public_network_access_enabled   = false
  tags                            = var.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
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
