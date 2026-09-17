# Read-only by Proxmox permission (terraform-bot's token has TerraformReadOnly
# on this resource's pool, not the full TerraformProvisioner role) - write
# access is a deliberate, temporary escalation only when actually rebuilding
# this container, never a standing capability. See home-server-talos README
# for the escalation procedure.
#
# The actual data (/zpool/data on the Proxmox host, ~940GB) is NOT part of
# this container's managed storage - it's a host-path bind mount (mp0 below),
# so even a full destroy+recreate of this container would leave that data
# untouched. rootfs below is just the 8GB Debian OS disk.

resource "proxmox_virtual_environment_container" "nfs_share" {
  node_name = local.talos_node
  vm_id     = 103

  started = true

  cpu {
    cores = 1
  }

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  memory {
    dedicated = 4096
    swap      = 1024
  }

  disk {
    datastore_id = "local-lvm"
    size         = 8
  }

  # Host bind mount, not a Proxmox-managed volume - "volume" is a raw
  # absolute path on the Proxmox host, so Terraform never provisions or
  # could destroy the underlying data.
  mount_point {
    volume = "/zpool/data"
    path   = "/mnt/data"
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    firewall    = true
    mac_address = "BC:24:11:19:96:05"
  }

  initialization {
    hostname = "nas"
    ip_config {
      ipv4 {
        address = "192.168.1.111/24"
        gateway = "192.168.1.1"
      }
    }
  }

  features {
    nesting = true
    mount   = ["nfs"]
  }

  operating_system {
    type = "debian"
    # Debian 12.7 confirmed via `pct exec 103 -- cat /etc/debian_version`;
    # this exact template was verified end-to-end on a throwaway container
    # (same `features: mount=nfs,nesting=1`) to actually produce a working
    # NFS server via ../ansible/nfs-server/playbook.yml - not a guess. This
    # field is under lifecycle.ignore_changes below, so it's documentation
    # for a real rebuild, not something Terraform enforces on live state.
    template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      disk,
      operating_system,
    ]
  }
}

import {
  to = proxmox_virtual_environment_container.nfs_share
  id = "${local.talos_node}/103"
}
