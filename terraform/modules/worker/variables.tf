variable "root_pool" {
    type = string
    description = "Pool to create root disk in."
    default = "default"
}

variable "mac_addrs" {
    type = list(string)
    description = "List of MAC addresses to pass to each VM for bootstrapping purposes. A master will be created for each MAC address."
}

variable "ram_size" {
    type = number
    description = "How many MiB of RAM to allocate for each worker."
    default = 8192
}

variable "vcpu_count" {
    type = number
    description = "Number of vCPUs to allocate for each worker."
    default = 4
}

variable "root_disk_size" {
    type = number
    description = "Size in bytes to allocate for root disk"
}

variable "data_disks" {
    type = list(string)
    description = "List of paths to block devices to pass through to each VM. Pass as many disks as you have workers."
}

variable "metadata_disk_size" {
    type = number
    description = "Size in bytes to allocate for metadata disk"
}

variable "bridge_name" {
    type = string
    description = "Name of bridge interface to create network access on"
}
