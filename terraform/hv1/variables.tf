# due to limitations with the libvirt provider (it does not properly
# populate the host variable for connections) we only support
# provisioning remote qemu+ssh libvirts :(
#
# 1) host: what host/ip you wish to remotely administer. defaults to localhost
# 2) user: what user to log in as. defaults to root.

# network resource you wish to deploy to.
variable "host" {
  type    = string
  default = "hv1.okd.example.com"
}

# user to authenticate to the resource as.
variable "user" {
  type    = string
  default = "root"
}

# root disk size
variable "root_disk_size" {
  default = 53687091200 # 50 GiB
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
# A worker will be created for each MAC address specified here.
variable worker_mac_addrs {
  default = [
    "c6:bf:52:b6:d8:4c",
    "c6:bf:52:19:a9:68",
    "c6:bf:52:e4:8e:9e"
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

# mac addresses for the masters for reservations
variable master_mac_addrs {
  default = [
    "c6:bf:52:d4:20:71"
  ]
}
