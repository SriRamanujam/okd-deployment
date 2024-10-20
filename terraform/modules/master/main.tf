terraform {
  required_version = ">= 1.2.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  }
}

resource "libvirt_volume" "master_root_disk" {
  count = length(var.mac_addrs)
  name  = "master_${replace(element(var.mac_addrs, count.index), ":", "")}_root"
  pool  = var.root_pool
  size  = var.root_disk_size
}

resource "libvirt_domain" "masters" {
  count    = length(var.mac_addrs)
  name     = "master_${replace(element(var.mac_addrs, count.index), ":", "")}"
  memory   = var.ram_size
  vcpu     = var.vcpu_count
  machine  = "q35"

  cpu {
    mode = "host-passthrough"
  }

  console {
    type        = "virtio"
    target_port = "0"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
  }

  video {
    type = "vga"
  }

  boot_device {
    dev = ["hd", "cdrom"]
  }


  network_interface {
    bridge = var.bridge_name
    mac    = element(var.mac_addrs, count.index)
  }


  disk {
    block_device = "/dev/${element(libvirt_volume.master_root_disk.*.pool, count.index)}/${element(libvirt_volume.master_root_disk.*.name, count.index)}"
  }

  disk {
    file = "/var/lib/libvirt/images/master.iso"
  }

  xml {
    xslt = file("${path.module}/../xslt/cdrom.xsl")
  }
}
