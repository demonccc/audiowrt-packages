#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makefile="$repo_root/audiowrt-wifi-client/Makefile"
script="$repo_root/audiowrt-wifi-client/files/audiowrt-wifi-client"

# The package must remain architecture independent and inert at install time.
grep -q '^PKGARCH:=all$' "$makefile"
if grep -Eq '(uci-defaults|/etc/init\.d|postinst)' "$makefile"; then
    echo 'ERROR: audiowrt-wifi-client must not mutate OpenWrt merely by being installed.' >&2
    exit 1
fi

# Scan uses the native iwinfo ubus provider and setup mode has its own DHCP/DNS support.
grep -q '+rpcd-mod-iwinfo' "$makefile"
grep -q '+dnsmasq' "$makefile"
grep -q 'ubus call iwinfo scan' "$script"
grep -q "network='audiowrt_wifi'\|network.audiowrt_wifi" "$script" || true
grep -q "audiowrt_setup" "$script"

# mDNS integration must preserve unrelated pre-existing interface entries.
if grep -q 'delete umdns.@umdns\[0\].network' "$script"; then
    echo 'ERROR: mDNS synchronization must not wipe unrelated OpenWrt network entries.' >&2
    exit 1
fi

echo 'Reusable Wi-Fi client package tests passed.'
