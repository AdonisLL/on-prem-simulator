variable "name_prefix" {
  type        = string
  description = "Lowercase resource naming prefix."
  default     = "opmlab"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,9}$", var.name_prefix))
    error_message = "name_prefix must be 3-10 lowercase alphanumeric characters and start with a letter."
  }
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "resource_group_name" {
  type    = string
  default = "rg-opmlab-source"
}

variable "deployment_id" {
  type        = string
  description = "Stable for one lab lifetime; change after teardown to avoid soft-deleted Key Vault name collisions."
  default     = "local01"
}

variable "tags" {
  type = map(string)
  default = {
    workload    = "on-prem-modernization-lab"
    environment = "lab"
  }
}

variable "enable_temporary_deployment_access" {
  type        = bool
  description = "Temporarily permits authenticated deployment-time Key Vault and Storage access. Lifecycle scripts disable it after guest configuration."
  default     = false
}

variable "address_prefixes" {
  type = object({
    vnet       = string
    bastion    = string
    management = string
    identity   = string
    web        = string
    data       = string
  })
  default = {
    vnet       = "10.50.0.0/16"
    bastion    = "10.50.0.0/26"
    management = "10.50.1.0/24"
    identity   = "10.50.2.0/24"
    web        = "10.50.3.0/24"
    data       = "10.50.4.0/24"
  }
}

variable "admin_username" {
  type    = string
  default = "labadmin"
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Generated deployment password. Store outside source control."
}

variable "vm_sizes" {
  type = object({
    dc        = string
    web       = string
    sql       = string
    appliance = string
  })
  default = {
    dc        = "Standard_B2ms"
    web       = "Standard_B2ms"
    sql       = "Standard_D4s_v5"
    appliance = "Standard_D8s_v5"
  }
}

variable "windows_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

variable "sql_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftSQLServer"
    offer     = "sql2016sp3-ws2019"
    sku       = "sqldev"
    version   = "latest"
  }
}

variable "enable_bastion" {
  type    = bool
  default = true
}

variable "auto_shutdown_time" {
  type    = string
  default = "1900"
}

variable "auto_shutdown_timezone" {
  type    = string
  default = "UTC"
}
