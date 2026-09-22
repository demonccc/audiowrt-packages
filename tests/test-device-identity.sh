#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Run the actual init functions against a fake sysfs and volatile directory.
. "$repo_root/audiowrt-identity/files/audiowrt-identity.init"
IDENTITY_NET_DIR="$tmp/net"
IDENTITY_PHY_DIR="$tmp/phy"
IDENTITY_DIR="$tmp/runtime"
logger() { :; }
uci() { echo 'Unexpected UCI call' >&2; exit 1; }
mkdir -p "$IDENTITY_NET_DIR/eth0" "$IDENTITY_PHY_DIR"
printf '00:11:22:33:44:55\n' > "$IDENTITY_NET_DIR/eth0/address"
printf '0\n' > "$IDENTITY_NET_DIR/eth0/addr_assign_type"
start
expected=a0d10a57-0000-8000-8000-001122334455
[[ "$(cat "$IDENTITY_DIR/uuid")" == "$expected" ]]
inode="$(stat -c %i "$IDENTITY_DIR/uuid")"
start
[[ "$(stat -c %i "$IDENTITY_DIR/uuid")" == "$inode" ]]
# Reconstruct after reboot-like removal: same identity, no persistent input.
rm "$IDENTITY_DIR/uuid"
start
[[ "$(cat "$IDENTITY_DIR/uuid")" == "$expected" ]]
printf '00:11:22:33:44:66\n' > "$IDENTITY_NET_DIR/eth0/address"
start
[[ "$(cat "$IDENTITY_DIR/uuid")" != "$expected" ]]

# Reject virtual/random addresses and USB dongles; allow onboard PHY fallback.
printf '1\n' > "$IDENTITY_NET_DIR/eth0/addr_assign_type"
mkdir -p "$tmp/devices/usb1/port/net/dongle"
printf '00:11:22:33:44:77\n' > "$tmp/devices/usb1/port/net/dongle/address"
printf '0\n' > "$tmp/devices/usb1/port/net/dongle/addr_assign_type"
ln -s "$tmp/devices/usb1/port/net/dongle" "$IDENTITY_NET_DIR/dongle"
rm "$IDENTITY_DIR/uuid"
if start; then echo 'Identity accepted nonpermanent or USB MAC' >&2; exit 1; fi
[[ ! -e "$IDENTITY_DIR/uuid" ]]
mkdir -p "$IDENTITY_PHY_DIR/phy0"
printf '00:11:22:33:44:88\n' > "$IDENTITY_PHY_DIR/phy0/macaddress"
start
[[ "$(cat "$IDENTITY_DIR/uuid")" == a0d10a57-0000-8000-8000-001122334488 ]]
for mac in 00:00:00:00:00:00 ff:ff:ff:ff:ff:ff 01:11:22:33:44:55 garbage; do
    if valid_identity_mac "$mac"; then echo "Invalid MAC accepted: $mac" >&2; exit 1; fi
done
echo 'Deterministic RAM-only identity tests passed.'
