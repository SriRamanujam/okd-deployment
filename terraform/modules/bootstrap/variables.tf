variable "root_pool" {
  type        = string
  description = "Pool to create root disk in."
  default     = "default"
}

variable "mac_addr" {
  type        = string
  description = "MAC addresses of bootstrap VM."
}

variable "root_disk_size" {
  type        = number
  description = "Size in bytes to allocate for root disk"
}

variable "bridge_name" {
  type        = string
  description = "Name of bridge interface to create network access on"
}
