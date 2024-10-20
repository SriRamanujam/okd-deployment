terraform {
  required_version = ">= 1.2.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  }
}

resource "libvirt_volume" "bootstrap_root_disk" {
  name = "bootstrap_root"
  pool = var.root_pool
  size = var.root_disk_size
}

resource "libvirt_domain" "bootstrap" {
  name   = "bootstrap"
  memory = 8192
  vcpu   = 4

  machine = "q35"

  cpu {
    mode = "host-passthrougH"
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

  disk {
    block_device = "/dev/${libvirt_volume.bootstrap_root_disk.pool}/${libvirt_volume.bootstrap_root_disk.name}"
  }

  disk {
    file = "/var/lib/libvirt/images/bootstrap.iso"
  }

  xml {
    xslt = file("${path.module}/../xslt/cdrom.xsl")
  }

  network_interface {
    bridge = var.bridge_name
    mac    = var.mac_addr
  }

}
