# due to limitations with the libvirt provider (it does not properly
# populate the host variable for connections) we only support
# provisioning remote qemu+ssh libvirts :(
#
# 1) host: what host/ip you wish to remotely administer. defaults to localhost
# 2) user: what user to log in as. defaults to root.
# 3) ssh_private_key_path: path to the private ssh key that gets you passwordless access to the user.

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

# path to private ssh key to allow passwordless access to the user account.
variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/id_rsa"
}

# root disk size
variable "root_disk_size" {
  default = 53687091200 # 50 GiB
}

# Fedora CoreOS version. left blank because this is always set by the tfvars.
variable "coreos_version" {

}

##### WORKER CONFIGURATION ####

# How many MiB of ram to allocate for the workers
variable "worker_ram_size" {
  default = 16384
}

# How many vcpus to allocate for the workers
variable "worker_vcpu_count" {
  default = 8
}

# worker mac addresses for reservation purposes.
variable worker_mac_addrs {
  default = [
    "c6:bf:52:e6:46:ee",
    "c6:bf:52:38:66:81",
    "c6:bf:52:67:87:e9"
  ]
}

# worker metadata disk size
variable "worker_metadata_disk_size" {
  default = 32212254720 # 30 GiB
}

# Paths to data disks for the worker VMs.
# There should always be as many data disks as VMs.
# Therefore, this array should always be the same length
# as the worker_mac_addrs array.
variable data_disks {
  default = [
    "/dev/sdc",
    "/dev/sdd",
    "/dev/sde"
  ]
}

##### MASTER CONFIGURATION ######

# number of masters to create on this host
variable "num_masters" {
  default = 1
}

# how many MiB of ram to allocate for the masters
variable "master_ram_size" {
  default = 10240
}

# how many vcpus to allocate for the masters
variable "master_vcpu_count" {
  default = 4
}

# mac address for the master that will live on this node
variable master_mac_addrs {
  default = [
    "c6:bf:52:0f:b3:d4"
  ]
}
