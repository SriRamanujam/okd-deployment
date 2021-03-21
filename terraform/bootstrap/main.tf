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

module "stacks_bootstrap" {
  source = "../modules/bootstrap"

  root_pool      = "ssd_pool"
  root_disk_size = var.bootstrap_root_disk_size
  ign_pool       = "default"
  ign_file       = file("${path.module}/../../config/bootstrap.ign")
  mac_addr       = var.bootstrap_mac_addr
  bridge_name    = "br0"
  fcos_version   = var.coreos_version
  rootfs         = module.fcos_base.fcos_base_rootfs

  host            = var.host
  ssh_private_key = file(var.ssh_private_key_path)
}
