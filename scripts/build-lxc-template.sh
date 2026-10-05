#!/usr/bin/env bash
# Builds the homelab LXC template from the stock Debian 13 one. Runs ON the
# Proxmox node as root (pct and the template storage are local to it):
#
#   scp scripts/build-lxc-template.sh ansible/keys/*.pub root@proxmox1:/tmp/tpl/
#   ssh root@proxmox1 /tmp/tpl/build-lxc-template.sh <version>
#
# Produces local:vztmpl/homelab-debian-13-<version>.tar.zst containing the
# ansible user, passwordless sudo, python3 and the guest + deploy PUBLIC keys,
# with root and password SSH login off and no host keys or machine-id (each
# guest generates its own on first boot). Refuses to overwrite a version.
#
# Env: STOCK_TEMPLATE (default local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst),
#      KEYS_DIR (default: this script's directory), SCRATCH_CTID (default 9999),
#      STORAGE (rootfs storage, default local-lvm), TEMPLATE_DIR (default /var/lib/vz/template/cache).

set -euo pipefail

version=${1:?usage: build-lxc-template.sh <version>}
stock=${STOCK_TEMPLATE:-local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst}
keys_dir=${KEYS_DIR:-$(cd "$(dirname "$0")" && pwd)}
ctid=${SCRATCH_CTID:-9999}
storage=${STORAGE:-local-lvm}
out_dir=${TEMPLATE_DIR:-/var/lib/vz/template/cache}
out="$out_dir/homelab-debian-13-$version.tar.zst"

[ ! -e "$out" ] || { echo "refusing to overwrite $out" >&2; exit 1; }
[ ! -e "/etc/pve/lxc/$ctid.conf" ] || { echo "scratch ctid $ctid is in use" >&2; exit 1; }
for k in guest_ed25519.pub deploy_ed25519.pub; do
  [ -s "$keys_dir/$k" ] || { echo "missing $keys_dir/$k" >&2; exit 1; }
done

cleanup() {
  pct stop "$ctid" >/dev/null 2>&1 || true
  pct destroy "$ctid" --purge >/dev/null 2>&1 || true
  command rm -f "${tmp_out:-}"
}
trap cleanup EXIT

pct create "$ctid" "$stock" --hostname template-build --unprivileged 1 \
  --rootfs "$storage:4" --net0 name=eth0,bridge=vmbr0,ip=dhcp --features nesting=1
pct start "$ctid"
# Wait for the network: apt below needs it.
for _ in $(seq 30); do pct exec "$ctid" -- getent hosts deb.debian.org >/dev/null 2>&1 && break; sleep 2; done

pct exec "$ctid" -- bash -euo pipefail -c '
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo python3 openssh-server
  id ansible >/dev/null 2>&1 || useradd --create-home --shell /bin/bash ansible
  install -d -m 700 -o ansible -g ansible /home/ansible/.ssh
  printf "ansible ALL=(ALL) NOPASSWD: ALL\n" > /etc/sudoers.d/ansible
  chmod 0440 /etc/sudoers.d/ansible
  visudo -csf /etc/sudoers.d/ansible
  printf "PermitRootLogin no\nPasswordAuthentication no\n" > /etc/ssh/sshd_config.d/10-homelab.conf
  # sshd keeps the first value it reads, and the stock sshd_config includes sshd_config.d at the top.
  cat > /etc/systemd/system/homelab-ssh-hostkeys.service <<UNIT
[Unit]
Description=Generate SSH host keys on first boot
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
UNIT
  systemctl enable homelab-ssh-hostkeys.service
'
cat "$keys_dir/guest_ed25519.pub" "$keys_dir/deploy_ed25519.pub" |
  pct exec "$ctid" -- bash -euo pipefail -c '
    cat > /home/ansible/.ssh/authorized_keys
    chown ansible:ansible /home/ansible/.ssh/authorized_keys
    chmod 600 /home/ansible/.ssh/authorized_keys'

pct exec "$ctid" -- bash -euo pipefail -c '
  apt-get clean
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
  rm -f /etc/ssh/ssh_host_*
  : > /etc/machine-id
  rm -f /var/lib/dbus/machine-id
  truncate -s 0 /root/.bash_history 2>/dev/null || true
'
pct stop "$ctid"

# The rootfs is a volume the node can mount; vzdump yields a tarball in the
# same layout a stock template has.
dump_dir=$(mktemp -d)
vzdump "$ctid" --mode stop --compress zstd --dumpdir "$dump_dir" >/dev/null
tmp_out="$out.partial"
# vzdump archives hold the rootfs under ./ plus metadata; extract and repack as a template.
work=$(mktemp -d)
tar --zstd -xf "$dump_dir"/vzdump-lxc-"$ctid"-*.tar.zst -C "$work"
tar --zstd -cf "$tmp_out" -C "$work" --exclude=./etc/vzdump .
command rm -rf "$work" "$dump_dir"
mv -n "$tmp_out" "$out"
tmp_out=
echo "built $out"
