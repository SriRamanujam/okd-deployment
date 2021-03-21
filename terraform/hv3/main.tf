terraform {
  required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.6.2"
    }
  }
}

provider "libvirt" {
    uri = "qemu+ssh://${var.user}@${var.host}/system"
}

module "fcos_base" {
    source = "../modules/fcos-base"

    fcos_version = var.coreos_version
}

module "stacks_masters" {
    source = "../modules/master"

    root_pool = "ssd_pool"
    ign_pool = "default"
    ign_file = file("${path.module}/../../config/master.ign")
    mac_addrs = var.master_mac_addrs
    ram_size = var.master_ram_size
    vcpu_count = var.master_vcpu_count
    root_disk_size = var.root_disk_size
    bridge_name = "br0"
    fcos_version = var.coreos_version
    rootfs = module.fcos_base.fcos_base_rootfs

    host = var.host
    ssh_private_key = file(var.ssh_private_key_path)
}

module "stacks_workers" {
    source = "../modules/worker"

    root_pool = "ssd_pool"
    ign_pool = "default"
    ign_file = file("${path.module}/../../config/worker.ign")
    mac_addrs = var.worker_mac_addrs
    ram_size = var.worker_ram_size
    vcpu_count = var.worker_vcpu_count
    root_disk_size = var.root_disk_size
    metadata_disk_size = var.worker_metadata_disk_size
    bridge_name = "br0"
    fcos_version = var.coreos_version
    rootfs = module.fcos_base.fcos_base_rootfs

    data_disks = var.data_disks

    host = var.host
    ssh_private_key = file(var.ssh_private_key_path)
}
