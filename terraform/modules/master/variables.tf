variable "root_pool" {
    type = string
    description = "Pool to create root disk in."
    default = "default"
}

variable "mac_addrs" {
    type = list(string)
    description = "List of MAC addresses to pass to each VM for bootstrapping purposes. A worker will be created for each mac address."
}

variable "ram_size" {
    type = number
    description = "How many MiB of RAM to allocate for each master."
    default = 16384
}

variable "vcpu_count" {
    type = number
    description = "Number of vCPUs to allocate for each master."
    default = 4
}

variable "root_disk_size" {
    type = number
    description = "Size in bytes to allocate for root disk"
}

variable "bridge_name" {
    type = string
    description = "Name of bridge interface to create network access on"
}
