variable "fcos_version" {
    type = string
    description = "FCOS version to deploy."
}

variable "root_pool" {
    type = string
    description = "Pool to create root disk in."
    default = "default"
}

variable "ign_pool" {
    type = string
    description = "Pool to create ignition files in."
    default = "default"
}

variable "ign_file" {
    description = "Ignition file to copy to virt host."
    default = "bootstrap.ign"
    type = string
}

variable "mac_addr" {
    type = string
    description = "MAC addresses of bootstrap VM."
}

variable "root_disk_size" {
    type = number
    description = "Size in bytes to allocate for root disk"
}

variable "bridge_name" {
    type = string
    description = "Name of bridge interface to create network access on"
}

variable "rootfs" {
    type = string
    description = "libvirt volume rootfs id"
}

variable "host" {
    type = string
    description = "hostname of libvirt virt host"
}

variable "ssh_private_key" {
    type = string
    description = "SSH private key file"
}
