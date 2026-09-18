#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makefile="$repo_root/audiowrt-wifi-client/Makefile"
script="$repo_root/audiowrt-wifi-client/files/audiowrt-wifi-client"
ui="$repo_root/luci-app-audiowrt-wifi-client/htdocs/luci-static/resources/view/audiowrt-wifi-client/client.js"
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
grep -q 'standalone BusyBox' "$script"
grep -q '\[ -x /usr/sbin/udhcpd \] || return 0' "$script"
grep -q '/etc/init.d/audiowrt-udhcpd restart' "$script"
grep -q 'option lease 600' "$script"
grep -q 'option router' "$script"
grep -q 'option dns' "$script"
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

# WPA personal credentials must be bounded to the normal 8..63 character PSK range.
grep -q '\${#key}.*-lt 8' "$script"
grep -q '\${#key}.*-gt 63' "$script"

# Current AudioWRT images use the native renderer for mDNS/DNS-SD. umdns is
# only a guarded backward-compatibility fallback and must never be required for
# provisioning to succeed.
grep -q '/usr/libexec/audiowrt-renderer' "$script"
grep -q '/etc/init.d/audiowrt-renderer reload' "$script"
grep -q '\[ -x /etc/init.d/umdns \]' "$script"
grep -q 'return 0' "$script"
if grep -q 'delete umdns.@umdns\[0\].network' "$script"; then
    echo 'ERROR: mDNS synchronization must not wipe unrelated OpenWrt network entries.' >&2
    exit 1
fi

echo 'Reusable Wi-Fi client package tests passed.'
