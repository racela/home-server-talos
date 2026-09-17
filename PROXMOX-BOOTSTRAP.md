# Rebuilding the Proxmox host from bare metal

Zero-dependency recovery steps for when the Proxmox host itself is gone -
not just a VM or the cluster, the actual physical machine. This is
deliberately kept in git rather than Otterwiki, since Otterwiki itself
runs on this same infrastructure and this doc needs to work before
anything else is running. Everything below was captured from the live
host on 2026-09-17, not assumed.

## 1. Install Proxmox VE

Manual - boot the Proxmox VE installer ISO, install normally. Version at
last capture: **8.4.1** (kernel 6.8.12-11-pve), single node (not part of
a Proxmox cluster). No non-default choices were identified for the boot
disk/`local-lvm` storage during this audit - the installer's defaults
are what's running.

Set the hostname to `proxmox` - the Terraform project
(`terraform/talos-vms.tf`, `terraform/nfs-lxc.tf`) hardcodes
`local.talos_node = "proxmox"` and expects the node to be reachable at
that name via the Proxmox API's `/nodes/proxmox/...` paths.

## 2. Network

Single NIC (`enp5s0`), single bridge (`vmbr0`), static IP. Exact content
of `/etc/network/interfaces`:

```
auto lo
iface lo inet loopback

iface enp5s0 inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.1.110/24
    gateway 192.168.1.1
    bridge-ports enp5s0
    bridge-stp off
    bridge-fd 0


source /etc/network/interfaces.d/*
```

## 3. The ZFS pool behind the NFS share

**This pool is a single disk with zero redundancy** - not a mirror or
raidz, just one drive. If that specific disk fails, this data is gone at
the hardware level; recovery means restoring immich's library from the
B2 backup and re-downloading Plex media (already-accepted trade-offs -
see `BACKUP-DR.md` in Otterwiki), not pool self-healing. Worth knowing
plainly rather than assuming redundancy exists.

Disk: `ata-WDC_WD80EFPX-68C4ZN0_WD-RD1Y8SHH` (8TB). Recreate with the
exact properties captured from the live pool (`ashift=12` and
`compression=on` were both explicitly set - `local` source, not
defaults; everything else below is a ZFS default, listed for
completeness):

```sh
zpool create -o ashift=12 -O compression=on zpool /dev/disk/by-id/ata-WDC_WD80EFPX-68C4ZN0_WD-RD1Y8SHH
```

This mounts at `/zpool` by default (matches live: `mountpoint=/zpool`,
`atime=on`, `recordsize=128K`, all unmodified defaults). The NFS
container's Terraform config expects the actual shared data at
`/zpool/data` specifically (`mp0: /zpool/data,mp=/mnt/data` - see
`terraform/nfs-lxc.tf`), so create that subdirectory before the NFS
container is created/imported:

```sh
mkdir -p /zpool/data
```

Actual data restoration into `/zpool/data` (immich library from B2,
Plex media re-download) is a separate step, not part of pool creation
itself.

## 4. terraform-bot user/role/token

Run `terraform/bootstrap-proxmox-user.sh` on the freshly installed host.
It creates the dedicated Proxmox user, both custom roles, both pools, the
API token, and every ACL grant this project's `.tf` files assume already
exist - see that script's own comments for why every grant is duplicated
across both the user and the token.

## 5. Creating the Talos VMs and NFS container fresh (not importing)

The `.tf` files as committed use `import {}` blocks, because they were
written to adopt already-existing infrastructure. On a genuine from-
scratch rebuild there is nothing to import - **remove (or comment out)
every `import {}` block** in `talos-vms.tf` and `nfs-lxc.tf` first, or
`terraform apply` will fail trying to import resources that don't exist.
With the import blocks removed, the same resource definitions will
instead *create* the VMs/container fresh: blank disks, the Talos ISO
attached (VMs) or the Debian template attached (container - see
`terraform/README.md`'s note on `operating_system.template_file_id`).

After `terraform apply` creates the 3 blank Talos VMs, they boot into
Talos maintenance mode from the attached ISO. From here, follow
`home-server-talos/README.md`'s existing recovery flow (`talhelper
genconfig` + `apply-config` per node) - with one addition only needed
for a genuine from-scratch cluster, not routine config changes: see the
new "Bootstrapping a cluster from scratch" section in that README.

The NFS container additionally needs `ansible/nfs-server/playbook.yml`
run against it after creation to actually configure it as an NFS server
- Terraform only manages its Proxmox-level shape, never what's installed
inside it. See that file's own header comment.
