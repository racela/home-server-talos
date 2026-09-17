#!/bin/sh
# Run once on a fresh Proxmox host, before the first `terraform init`/`apply`.
# Creates the dedicated terraform-bot user/roles/pools/token this project's
# .tf files assume already exist. Not idempotent by design - re-running
# against an already-bootstrapped host will fail loudly on the first
# already-exists error rather than silently no-op, which is safer than
# masking a real "did this already run?" question during a disaster.
#
# The pveum privilege-separation gotcha that cost real debugging time
# building this the first time: a token's effective permission is the
# INTERSECTION of the parent user's permissions and the token's own -
# every grant below is duplicated for both --users and --tokens, or the
# token ends up with zero effective access regardless of its own role.
#
# See ../README.md and this directory's own README.md for the full story.

set -eu

TOKEN_ID='terraform-bot@pve!tf-token'

pveum user add terraform-bot@pve --comment "Terraform provisioning runner"

pveum role add TerraformProvisioner -privs \
  "VM.Allocate,VM.Clone,VM.Config.CDROM,VM.Config.CPU,VM.Config.Disk,\
VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Config.HWType,\
VM.Console,VM.Monitor,VM.Audit,VM.PowerMgmt,VM.Backup,\
Datastore.AllocateSpace,Datastore.Audit,Sys.Audit"

pveum role add TerraformReadOnly -privs "VM.Audit,Datastore.Audit,Sys.Audit"

pveum pool add talos-cluster --comment "VMs managed by Terraform"
pveum pool add nfs-storage --comment "Read-only tracked in Terraform"

# Add the 3 Talos VMs and the NFS container to their pools once they exist
# (either freshly created by `terraform apply`, or already present on a
# host that's just getting terraform-bot bootstrapped after the fact).
# Uncomment once the VM IDs are live:
# pveum pool modify talos-cluster --vms 100,101,102
# pveum pool modify nfs-storage --vms 103

pveum user token add terraform-bot@pve tf-token --comment "Terraform provider auth"
echo ""
echo ">>> Save the token secret printed above to your password manager NOW."
echo ">>> It is shown exactly once and cannot be retrieved again."
echo ""

pveum acl modify /pool/talos-cluster --users terraform-bot@pve --roles TerraformProvisioner
pveum acl modify /pool/talos-cluster --tokens "$TOKEN_ID" --roles TerraformProvisioner
pveum acl modify /pool/nfs-storage --users terraform-bot@pve --roles TerraformReadOnly
pveum acl modify /pool/nfs-storage --tokens "$TOKEN_ID" --roles TerraformReadOnly

# Storage has its own separate permission tree from the VM tree - needed
# because both the Talos VMs' and the NFS container's disks live on
# local-lvm, and reading disk metadata during import/apply needs this
# regardless of which VM is involved.
pveum acl modify /storage/local-lvm --users terraform-bot@pve --roles TerraformProvisioner
pveum acl modify /storage/local-lvm --tokens "$TOKEN_ID" --roles TerraformProvisioner

echo "Done. Verify with: pveum acl list"
