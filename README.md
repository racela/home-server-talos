# home-server-talos

Declarative machine config for the `home-server` Talos cluster (3 nodes,
all control-plane: `talos-01/02/03` at `192.168.1.121-123`, VIP
`192.168.1.120`), managed with [talhelper](https://github.com/budimanjojo/talhelper)
and encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age).

Kubernetes-level workloads live in the separate
[`home-server-argocd`](https://github.com/racela/home-server-argocd) repo.
This repo only covers the Talos OS / machine-config layer underneath it.

## Files

- `talconfig.yaml` — cluster + per-node definition (versions, endpoint,
  network, disks). Edit this for most changes.
- `talsecret.yaml` — the cluster's actual PKI and tokens (etcd/k8s/OS CAs,
  service account key, bootstrap/trustd tokens), encrypted with SOPS+age.
  Safe to commit/push as-is; useless without the age private key.
- `.sops.yaml` — which age public key encrypts `talsecret.yaml`.
- `patches/` — non-secret machine-config fragments referenced from
  `talconfig.yaml`'s `patches:` list (`common.yaml`, `kubelet.yaml`,
  `longhorn-image.yaml`). `longhorn-extensions.yaml` is documentation only
  (the Image Factory schematic behind `longhorn-image.yaml`'s image) — it's
  not a valid machine-config field, so it's intentionally not wired in.
- `clusterconfig/` (gitignored) — generated output: per-node machine
  configs in plaintext and a client `talosconfig`. Regenerated on demand,
  never committed.

## Authenticating to the cluster / recovering access

You need exactly two durable things, both already backed up outside this
machine:

1. **This repo** (GitHub, private).
2. **The age private key** that decrypts `talsecret.yaml` — stored in the
   password manager. Without it, `talsecret.yaml` is just ciphertext and
   nothing here can be regenerated.

From a fresh machine with those two:

```sh
# 1. Install tools (no sudo needed — see install notes below)
# talhelper, sops, age, talosctl

# 2. Clone this repo
git clone git@github.com:racela/home-server-talos.git
cd home-server-talos

# 3. Put the age private key in the default SOPS lookup path
mkdir -p ~/.config/sops/age
# paste the key from your password manager into:
#   ~/.config/sops/age/talos-home-server.key

# 4. Generate a fresh admin client cert + node configs
export SOPS_AGE_KEY_FILE=~/.config/sops/age/talos-home-server.key
talhelper genconfig

# 5. Install the generated client config as your active talosctl context
talosctl config merge ./clusterconfig/talosconfig
talosctl config context home-server

# 6. Verify
talosctl -n 192.168.1.121 version
kubectl get nodes   # needs a kubeconfig too, see note below
```

The admin client cert `talhelper genconfig` mints is signed by the OS CA
already trusted by the running nodes, so this works immediately as long as
you can reach the node IPs (same LAN, or the Tailscale subnet router if
that's up and you're remote — note that won't help if the whole cluster is
down, since it runs on the cluster).

`kubectl` access additionally needs a kubeconfig, which isn't stored here
(K8s-level concerns live in `home-server-argocd`) — generate one with
`talosctl kubeconfig` once you're authenticated to Talos.

### Install notes (Arch Linux, no sudo)

`sops` and `age` are in the official Arch repos (`pacman -S sops age`) if
you have sudo available. Without it, or for `talhelper` (AUR-only),
download static binaries to `~/.local/bin`:

```sh
curl -sL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" -o ~/.local/bin/yq
curl -sL "https://github.com/FiloSottile/age/releases/latest/download/age-<version>-linux-amd64.tar.gz" | tar -xz -C /tmp
cp /tmp/age/age /tmp/age/age-keygen ~/.local/bin/
# sops: grab the linux.amd64 binary from https://github.com/getsops/sops/releases/latest
# talhelper: grab the linux_amd64 tarball from https://github.com/budimanjojo/talhelper/releases/latest
chmod +x ~/.local/bin/*
```

## Making a change

1. Edit `talconfig.yaml` / `patches/*.yaml` as needed.
2. `talhelper genconfig` to regenerate `clusterconfig/`.
3. **Dry-run first, per node:**
   ```sh
   talosctl apply-config --talosconfig=./clusterconfig/talosconfig \
     --nodes=<node-ip> --file=./clusterconfig/home-server-<node>.yaml --dry-run
   ```
   Review the diff carefully — machine configs embed secrets inline, so
   never pipe this output anywhere it might get logged/shared unredacted.
4. Apply **one node at a time**, checking health before moving to the
   next (this is a 3-node etcd cluster — never apply to all three at once):
   ```sh
   talosctl apply-config --talosconfig=./clusterconfig/talosconfig \
     --nodes=<node-ip> --file=./clusterconfig/home-server-<node>.yaml
   talosctl -n <node-ip> health --server=false
   kubectl get nodes
   ```
5. Commit and push `talconfig.yaml` / `patches/` / `talsecret.yaml` (never
   `clusterconfig/` — it's gitignored on purpose).

Before any change that touches live nodes, consider taking a manual etcd
snapshot as a safety net:

```sh
talosctl -n <any-control-plane-ip> etcd snapshot ./pre-change-snapshot.db
```

## Rotating the admin client certificate

The admin cert `talhelper genconfig` produces is minted fresh (new 1-year
validity) from the OS CA every time it runs — no need to touch cluster PKI
to rotate it:

```sh
talhelper genconfig
talosctl config merge ./clusterconfig/talosconfig
talosctl config context home-server
```
