locals {
  scenario       = "nested-virtualization"
  azure_vm_roles = ["hyperv01"]
  subnets        = [var.host_subnet_name]
  host_vm_name   = "${var.name_prefix}-hyperv01"
  tags = merge(var.tags, {
    scenario = local.scenario
    workload = "on-prem-modernization-lab"
  })
}

resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "${var.name_prefix}-nested-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.240.0.0/16"]
  tags                = local.tags
}

resource "azurerm_network_security_group" "host" {
  name                = "${local.host_vm_name}-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_subnet" "host" {
  name                 = var.host_subnet_name
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.host_subnet_prefix]
}

resource "azurerm_subnet_network_security_group_association" "host" {
  subnet_id                 = azurerm_subnet.host.id
  network_security_group_id = azurerm_network_security_group.host.id
}

resource "azurerm_network_interface" "host" {
  name                = "${local.host_vm_name}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.host.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.host_private_address
  }
}

resource "azurerm_managed_disk" "guest_data" {
  name                 = "${local.host_vm_name}-data"
  location             = azurerm_resource_group.lab.location
  resource_group_name  = azurerm_resource_group.lab.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.host_data_disk_size_gb
  tags                 = local.tags
}

resource "terraform_data" "host_vm" {
  triggers_replace = {
    resource_group_name = azurerm_resource_group.lab.name
    location            = azurerm_resource_group.lab.location
    vm_name             = local.host_vm_name
    nic_id              = azurerm_network_interface.host.id
    data_disk_id        = azurerm_managed_disk.guest_data.id
    host_vm_size        = var.host_vm_size
    image               = join(":", [var.host_image.publisher, var.host_image.offer, var.host_image.sku, var.host_image.version])
    admin_username      = var.admin_username
  }

  provisioner "local-exec" {
    command     = "${path.module}\\scripts\\create-host.ps1"
    interpreter = ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-File"]
    environment = {
      RESOURCE_GROUP_NAME  = self.triggers_replace.resource_group_name
      LOCATION             = self.triggers_replace.location
      VM_NAME              = self.triggers_replace.vm_name
      NIC_ID               = self.triggers_replace.nic_id
      DATA_DISK_ID         = self.triggers_replace.data_disk_id
      HOST_VM_SIZE         = self.triggers_replace.host_vm_size
      HOST_IMAGE_PUBLISHER = var.host_image.publisher
      HOST_IMAGE_OFFER     = var.host_image.offer
      HOST_IMAGE_SKU       = var.host_image.sku
      HOST_IMAGE_VERSION   = var.host_image.version
      ADMIN_USERNAME       = self.triggers_replace.admin_username
      ADMIN_PASSWORD       = var.admin_password
    }
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "${path.module}\\scripts\\remove-host.ps1"
    interpreter = ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-File"]
    environment = {
      RESOURCE_GROUP_NAME = self.triggers_replace.resource_group_name
      VM_NAME             = self.triggers_replace.vm_name
    }
  }
}
