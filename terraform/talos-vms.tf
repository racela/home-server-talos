# node_name assumed to be "proxmox" from the shell prompt (root@proxmox:~#)
# seen when running qm config - correct this if the actual Proxmox node
# name differs (check the web UI's left sidebar, or `pvecm status`).

locals {
  talos_node = "proxmox"

  talos_vms = {
    "talos-01" = {
      vm_id       = 100
      mac_address = "BC:24:11:E8:EC:97"
    }
    "talos-02" = {
      vm_id       = 101
      mac_address = "BC:24:11:BB:CC:4C"
    }
    "talos-03" = {
      vm_id       = 102
      mac_address = "BC:24:11:85:BA:D5"
    }
  }
}

resource "proxmox_virtual_environment_vm" "talos" {
  for_each = local.talos_vms

  name      = each.key
  node_name = local.talos_node
  vm_id     = each.value.vm_id

  # These are existing, already-running nodes - Terraform must never
  # power-cycle or reinstall them as a side effect of applying config.
  started         = true
  on_boot         = true
  stop_on_destroy = true

  agent {
    enabled = false # Talos doesn't run the QEMU guest agent
  }

  cpu {
    cores   = 3
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192
  }

  scsi_hardware = "virtio-scsi-single" # provider default is virtio-scsi-pci - must pin this to match reality, not a cosmetic field

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
    iothread     = true
  }

  cdrom {
    file_id = "local:iso/talos-1.10.2-amd64.iso"
  }

  network_device {
    bridge      = "vmbr0"
    firewall    = true
    mac_address = each.value.mac_address
  }

  operating_system {
    type = "l26"
  }

  boot_order = ["scsi0", "ide2", "net0"]

  lifecycle {
    prevent_destroy = true
    # Talos manages its own OS/disk state after install - Terraform
    # should never try to "fix" drift on these by reinstalling.
    ignore_changes = [
      cdrom,
      disk,
    ]
  }
}

import {
  to = proxmox_virtual_environment_vm.talos["talos-01"]
  id = "${local.talos_node}/100"
}

import {
  to = proxmox_virtual_environment_vm.talos["talos-02"]
  id = "${local.talos_node}/101"
}

import {
  to = proxmox_virtual_environment_vm.talos["talos-03"]
  id = "${local.talos_node}/102"
}
