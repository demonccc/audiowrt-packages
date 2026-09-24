#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makefile="$repo_root/audiowrt-wifi-client/Makefile"
script="$repo_root/audiowrt-wifi-client/files/audiowrt-wifi-client"
ui="$repo_root/luci-app-audiowrt-network-client/htdocs/luci-static/resources/view/audiowrt-network-client/client.js"
wizard="$repo_root/audiowrt-provisioning/files/audiowrt.html"
busybox_makefile="$repo_root/audiowrt-busybox/Makefile"
udhcpd_makefile="$repo_root/audiowrt-udhcpd/Makefile"

# The package must remain architecture independent and inert at install time.
grep -q '^PKGARCH:=all$' "$makefile"
if grep -Eq '(uci-defaults|/etc/init\.d|postinst)' "$makefile"; then
    echo 'ERROR: audiowrt-wifi-client must not mutate OpenWrt merely by being installed.' >&2
    exit 1
fi

# Scan uses the native iwinfo ubus provider. DHCP and mDNS are selected by the
# firmware flavor, not pulled in implicitly by this reusable client package.
grep -q '+rpcd-mod-iwinfo' "$makefile"
grep -q "echo 'CONFIG_UDHCPD=y'" "$busybox_makefile"
grep -q '+audiowrt-busybox' "$udhcpd_makefile"
if grep -Eq 'usr/sbin/udhcpd|ln -sf .*/bin/busybox' "$udhcpd_makefile"; then
    echo 'ERROR: audiowrt-busybox must own the udhcpd applet; audiowrt-udhcpd is configuration/service only.' >&2
    exit 1
fi
if grep -Eq '\+dnsmasq|\+umdns' "$makefile"; then
    echo 'ERROR: DHCP/DNS and mDNS services must remain flavor-owned.' >&2
    exit 1
fi
grep -q 'ubus call iwinfo scan' "$script"
grep -q "network.audiowrt_wifi='interface'" "$script"
grep -q "wireless.audiowrt_client='wifi-iface'" "$script"
grep -q 'audiowrt_setup' "$script"
grep -q "printf 'signal=%s" "$script"
grep -q "printf 'channel=%s" "$script"
grep -q "printf 'rx_bitrate=%s" "$script"
grep -q "printf 'tx_bitrate=%s" "$script"
grep -q "printf 'runtime_ip=%s" "$script"
grep -q "printf 'rx_bytes=%s" "$script"
grep -q "printf 'tx_bytes=%s" "$script"
ap="$repo_root/audiowrt-provisioning/files/setup-ap"
grep -q 'udhcpd -f' "$ap"
grep -q 'max_leases 100' "$ap"
grep -q 'lease_file $AUDIOWRT_SETUP_DIR/leases' "$ap"
grep -q 'option lease 600' "$ap"
if grep -Eq 'uci -q commit dhcp|dhcp\.audiowrt_setup' "$script"; then
    echo 'ERROR: standalone provisioning DHCP must not depend on /etc/config/dhcp.' >&2
    exit 1
fi
if grep -Eq 'dnsmasq|setup_dns|odhcpd' "$script"; then
    echo 'ERROR: Wi-Fi provisioning must use BusyBox udhcpd, not dnsmasq/odhcpd.' >&2
    exit 1
fi

# The AudioWRT Wi-Fi client owns IPv4 setup so luci-mod-network is not required.
grep -q '^configure_ip()' "$script"
grep -q "network.audiowrt_wifi.proto='dhcp'" "$script"
grep -q "network.audiowrt_wifi.proto='static'" "$script"
grep -q 'network.audiowrt_wifi.ipaddr=' "$script"
grep -q 'network.audiowrt_wifi.netmask=' "$script"
grep -q 'network.audiowrt_wifi.gateway=' "$script"
grep -q 'add_list network.audiowrt_wifi.dns=' "$script"
grep -q "_('Automatic (DHCP)')" "$ui"
grep -q "_('Manual')" "$ui"
grep -q "_('IP address')" "$ui"
grep -q "_('Netmask')" "$ui"
grep -q "_('Gateway')" "$ui"
grep -q "_('Primary DNS (optional)')" "$ui"

# Scan presentation must use per-BSSID capability data instead of inferring
# Wi-Fi generation from frequency alone.
for view in "$ui" "$wizard"; do
    grep -q 'ht_operation' "$view"
    grep -q 'vht_operation' "$view"
    grep -q 'he_operation' "$view"
    grep -q 'eht_operation' "$view"
    grep -q 'Wi-Fi' "$view"
    grep -q '2.4 GHz' "$view"
    grep -q '5 GHz' "$view"
    grep -q '6 GHz' "$view"
done

# WPA personal credentials must be bounded to the normal 8..63 character PSK range.
grep -q '\${#key}.*-lt 8' "$script"
grep -q '\${#key}.*-gt 63' "$script"

# Current AudioWRT images use the native renderer for mDNS/DNS-SD. umdns is
# only a guarded backward-compatibility fallback and must never be required for
# provisioning to succeed.
grep -q 'pidof audiowrt-renderer' "$script"
grep -q 'kill -HUP' "$script"
grep -q '\[ -x /etc/init.d/umdns \]' "$script"
grep -q 'return 0' "$script"
if grep -q 'delete umdns.@umdns\[0\].network' "$script"; then
    echo 'ERROR: mDNS synchronization must not wipe unrelated OpenWrt network entries.' >&2
    exit 1
fi

echo 'Reusable Wi-Fi client package tests passed.'
