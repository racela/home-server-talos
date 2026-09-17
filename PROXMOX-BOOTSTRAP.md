# Rebuilding the Proxmox host from bare metal

Zero-dependency recovery steps for when the Proxmox host itself is gone -
not just a VM or the cluster, the actual physical machine. This is
deliberately kept in git rather than Otterwiki, since Otterwiki itself
runs on this same infrastructure and this doc needs to work before
anything else is running. Everything below was captured from the live
host on 2026-09-17, not assumed.

## 1. Install Proxmox VE (automated)

`proxmox-install/` in this repo has everything needed for an unattended
install: `answer.toml` (network config, disk targeting) and
`first-boot-zfs.sh` (creates the ZFS pool automatically on first boot -
see its own header for why it deliberately does NOT also run the
terraform-bot bootstrap). Fill in `answer.toml`'s two placeholders first
(`root-password-hashed` via `mkpasswd -m sha-512`, optionally
`root-ssh-keys`) - never real secrets committed to git.

On any Linux machine with `proxmox-auto-install-assistant` installed
(`apt install proxmox-auto-install-assistant`, or download a current
Proxmox VE ISO and run it from there):

```sh
proxmox-auto-install-assistant validate-answer proxmox-install/answer.toml

proxmox-auto-install-assistant prepare-iso /path/to/proxmox-ve_8.x.iso \
  --fetch-from iso \
  --answer-file proxmox-install/answer.toml \
  --on-first-boot proxmox-install/first-boot-zfs.sh
```

Flash the resulting ISO to a USB drive, boot the target hardware from
it. Everything else - partitioning, network, hostname, the ZFS pool -
happens unattended. Regenerating the ISO (e.g. to pick up a new Proxmox
point release, or after editing `answer.toml`) is just re-running the
command above - cheap enough that there's no real reason to keep a
generic ISO around separately from a site-specific one.

**The one genuinely irreducible manual step**: physically getting this
ISO onto the target hardware and selecting it as the boot device. Only
avoidable with out-of-band remote management (IPMI/BMC with virtual
media) - not confirmed whether this host has that.

Set the hostname to `proxmox` (already in `answer.toml`'s `fqdn`) - the
Terraform project (`terraform/talos-vms.tf`, `terraform/nfs-lxc.tf`)
hardcodes `local.talos_node = "proxmox"` and expects the node reachable
at that name via the Proxmox API's `/nodes/proxmox/...` paths.

### Manual fallback / what the automation is actually doing

If not using the automated install, or for reference/troubleshooting:
single NIC (`enp5s0`), single bridge (`vmbr0`), static IP. Exact content
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

The ZFS pool behind the NFS share - **a single disk with zero
redundancy**, not a mirror or raidz. If that specific disk fails, this
data is gone at the hardware level; recovery means restoring immich's
library from the B2 backup and re-downloading Plex media
(already-accepted trade-offs - see `BACKUP-DR.md` in Otterwiki), not
pool self-healing. Worth knowing plainly rather than assuming redundancy
exists. Disk: `ata-WDC_WD80EFPX-68C4ZN0_WD-RD1Y8SHH` (8TB). Recreate with
the exact properties captured from the live pool (`ashift=12` and
`compression=on` were both explicitly set - `local` source, not
defaults; everything else is an unmodified ZFS default):

```sh
zpool create -o ashift=12 -O compression=on zpool /dev/disk/by-id/ata-WDC_WD80EFPX-68C4ZN0_WD-RD1Y8SHH
mkdir -p /zpool/data
```

If the ZFS disk itself failed (not just the host) and is being replaced,
its `by-id` path will differ from the one above - check
`ls /dev/disk/by-id/` on the new hardware first.

## 2. terraform-bot user/role/token

Run `terraform/bootstrap-proxmox-user.sh` on the freshly installed host.
It creates the dedicated Proxmox user, both custom roles, both pools, the
API token, and every ACL grant this project's `.tf` files assume already
exist - see that script's own comments for why every grant is duplicated
across both the user and the token.

## 3. Creating the Talos VMs and NFS container fresh (not importing)

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
