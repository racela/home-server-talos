#!/bin/sh
# Runs automatically on first boot after an automated Proxmox install
# (see answer.toml's [first-boot] section). Self-contained and secret-free
# by design - only creates the ZFS data pool, nothing that needs a human
# to capture a printed credential. The terraform-bot bootstrap
# (bootstrap-proxmox-user.sh, ../terraform/) stays a separate manual step
# for exactly that reason - see ../PROXMOX-BOOTSTRAP.md.
#
# ashift=12 and compression=on match the live pool's actual properties
# (`zpool get ashift ...` / `zfs get compression ...`, captured
# 2026-09-17) - both are immutable pool-creation-time choices, unlike
# atime/recordsize/mountpoint which are plain ZFS defaults here.

set -eu

# This assumes the SAME physical ZFS disk survives and is being attached
# to freshly-installed Proxmox (e.g. motherboard died, disk didn't). If
# the disk itself failed and is being replaced, its by-id path will be
# different - check `ls /dev/disk/by-id/` on the new hardware and update
# this before running, and note that recreating the pool on a genuinely
# new disk means restoring immich's library from the B2 backup and
# re-downloading Plex media, not just an empty pool (see BACKUP-DR.md in
# Otterwiki and PROXMOX-BOOTSTRAP.md's redundancy note).
DISK_ID="ata-WDC_WD80EFPX-68C4ZN0_WD-RD1Y8SHH"

if zpool list zpool >/dev/null 2>&1; then
    echo "zpool already exists, skipping creation"
else
    zpool create -o ashift=12 -O compression=on zpool "/dev/disk/by-id/${DISK_ID}"
fi

mkdir -p /zpool/data
