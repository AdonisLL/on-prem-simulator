variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "vm_name" { type = string }
variable "role" { type = string }
variable "vm_size" { type = string }
variable "admin_username" { type = string }
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "subnet_id" { type = string }
variable "private_ip_address" { type = string }
variable "image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}
variable "trusted_launch" { type = bool }
variable "os_disk_size_gb" { type = number }
variable "data_disk_size_gb" { type = number }
variable "auto_shutdown_time" { type = string }
variable "auto_shutdown_timezone" { type = string }
variable "tags" { type = map(string) }
