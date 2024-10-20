terraform {
  required_version = ">= 1.2.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  }
}

provider "libvirt" {
    uri = "qemu+ssh://${var.user}@${var.host}/system"
}

module "stacks_masters" {
    source = "../modules/master"

    root_pool = "ssd_pool"
    mac_addrs = var.master_mac_addrs
    ram_size = var.master_ram_size
    vcpu_count = var.master_vcpu_count
    root_disk_size = var.root_disk_size
    bridge_name = "br0"
}

module "stacks_workers" {
    source = "../modules/worker"

    root_pool = "ssd_pool"
    mac_addrs = var.worker_mac_addrs
    ram_size = var.worker_ram_size
    vcpu_count = var.worker_vcpu_count
    root_disk_size = var.root_disk_size
    metadata_disk_size = var.worker_metadata_disk_size
    data_disks = var.data_disks
    bridge_name = "br0"
}
