terraform {
  required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.6.2"
    }
  }
}

resource "libvirt_ignition" "worker_ign" {
    pool = var.ign_pool
    name = "worker.ign"
    content = var.ign_file
}

resource "libvirt_volume" "worker_root_disk" {
    count = length(var.mac_addrs)
    name = "worker_${replace(element(var.mac_addrs, count.index), ":", "")}_root"
    pool = var.root_pool
    size = var.root_disk_size

    provisioner "remote-exec" {
        inline = [
            "dd if=${var.rootfs} of=/dev/${self.pool}/${self.name} oflag=direct bs=10M"
        ]

        connection {
            type        = "ssh"
            user        = "root"
            host        = var.host
            private_key = var.ssh_private_key
        }
    }
}

resource "libvirt_volume" "worker_ceph_metadata_disk" {
    count = length(var.mac_addrs)
    name = "worker_${replace(element(var.mac_addrs, count.index), ":", "")}_metadata"
    pool = var.root_pool
    size = var.metadata_disk_size

    provisioner "remote-exec" {
        inline = [
            "dd if=/dev/zero of=/dev/${self.pool}/${self.name} bs=1M count=2"
        ]

        connection {
            type        = "ssh"
            user        = "root"
            host        = var.host
            private_key = var.ssh_private_key
        }
    }
}

resource "libvirt_domain" "workers" {
    count = length(var.mac_addrs)
    name = "worker_${replace(element(var.mac_addrs, count.index), ":", "")}"
    memory = var.ram_size
    vcpu = var.vcpu_count

    coreos_ignition = libvirt_ignition.worker_ign.id

    network_interface {
        bridge = var.bridge_name
        mac = element(var.mac_addrs, count.index)
    }

    video {
        type = "virtio"
    }

    disk {
        volume_id = element(libvirt_volume.worker_root_disk.*.id, count.index)
    }

    disk {
        volume_id = element(libvirt_volume.worker_ceph_metadata_disk.*.id, count.index)
    }

    disk {
        block_device = element(var.data_disks, count.index)
    }
}
