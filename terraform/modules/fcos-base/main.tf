terraform {
  required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.6.2"
    }
  }
}

resource "null_resource" "download_fcos_image" {
    provisioner "local-exec" {
         command = "curl -LO -s https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${var.fcos_version}/x86_64/fedora-coreos-${var.fcos_version}-qemu.x86_64.qcow2.xz && unxz fedora-coreos-${var.fcos_version}-qemu.x86_64.qcow2.xz && qemu-img convert -f qcow2 -O raw fedora-coreos-${var.fcos_version}-qemu.x86_64.qcow2 fedora-coreos-${var.fcos_version}-qemu.x86_64.raw && rm -f fedora-coreos-${var.fcos_version}-qemu.x86_64.qcow2"

         working_dir="/var/tmp"
    }
}

resource "libvirt_volume" "fcos_base_rootfs" {
    source = "/var/tmp/fedora-coreos-${var.fcos_version}-qemu.x86_64.raw"
    name = "fedora-coreos-${var.fcos_version}-qemu.x86_64.raw"
    pool = var.pool
    format = "raw"

    depends_on = [
        null_resource.download_fcos_image
    ]
}
