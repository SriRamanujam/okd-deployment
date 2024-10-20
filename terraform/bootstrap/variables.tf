# due to limitations with the libvirt provider (it does not properly
# populate the host variable for connections) we only support
# provisioning remote qemu+ssh libvirts :(
#
# 1) host: what host/ip you wish to remotely administer. defaults to localhost
# 2) user: what user to log in as. defaults to root.

# network resource you wish to deploy to.
variable "host" {
  type    = string
  default = "hv3.okd.example.com"
}

# user to authenticate to the resource as.
variable "user" {
  type    = string
  default = "root"
}

# mac address for bootstrap vm for reservation
variable bootstrap_mac_addr {
  default = "c6:bf:52:22:1e:dd"
}

# bootstrap root disk size
variable bootstrap_root_disk_size {
  default = 128849018880 # 120 GiB (any less and the bootstrap will fail due to running out of tmpfs space)
}
