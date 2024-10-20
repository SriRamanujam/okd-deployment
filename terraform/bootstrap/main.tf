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

module "stacks_bootstrap" {
  source = "../modules/bootstrap"

  root_pool      = "ssd_pool"
  root_disk_size = var.bootstrap_root_disk_size
  mac_addr       = var.bootstrap_mac_addr
  bridge_name    = "br0"
}
