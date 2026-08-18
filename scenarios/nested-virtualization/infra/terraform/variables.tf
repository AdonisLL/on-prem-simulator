variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "name_prefix" {
  type    = string
  default = "opmlab"
}

variable "admin_username" {
  type    = string
  default = "labadmin"
}

variable "admin_password" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "host_vm_size" {
  type    = string
  default = "Standard_D32s_v5"
}

variable "host_image" {
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

variable "host_data_disk_size_gb" {
  type    = number
  default = 1024
}

variable "host_subnet_name" {
  type    = string
  default = "snet-hyperv-host"
}

variable "host_subnet_prefix" {
  type    = string
  default = "10.240.0.0/24"
}

variable "host_private_address" {
  type    = string
  default = "10.240.0.10"
}

variable "tags" {
  type    = map(string)
  default = {}
}
