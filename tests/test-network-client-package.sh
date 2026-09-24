#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makefile="$repo_root/audiowrt-network-client/Makefile"
script="$repo_root/audiowrt-network-client/files/audiowrt-network-client"
luci_makefile="$repo_root/luci-app-audiowrt-network-client/Makefile"
ui="$repo_root/luci-app-audiowrt-network-client/htdocs/luci-static/resources/view/audiowrt-network-client/client.js"
menu="$repo_root/luci-app-audiowrt-network-client/root/usr/share/luci/menu.d/luci-app-audiowrt-network-client.json"
compat="$repo_root/luci-app-audiowrt-wifi-client/Makefile"

grep -q '^PKGARCH:=all$' "$makefile"
grep -q '+audiowrt-config' "$makefile"
grep -q '+netifd' "$makefile"
if grep -Eq '(uci-defaults|/etc/init\.d|postinst)' "$makefile"; then
    echo 'ERROR: audiowrt-network-client must remain inert at install time.' >&2
    exit 1
fi

# Ethernet status is runtime-derived, including link, active address/route and counters.
grep -q "ETH_INTERFACE='lan'" "$script"
grep -q 'network.interface.$ETH_INTERFACE' "$script"
grep -q '/statistics/rx_bytes' "$script"
grep -q '/statistics/tx_bytes' "$script"
grep -q '/carrier' "$script"
grep -q '/speed' "$script"
grep -q '/duplex' "$script"
grep -q 'active_route=' "$script"
grep -q 'ethernet_runtime_ip=' "$script"
grep -q 'ethernet_runtime_gateway=' "$script"
grep -q 'ethernet_runtime_dns=' "$script"

# Ethernet configuration is explicit and persists only through AudioWRT's save helper.
grep -q 'configure-ethernet' "$script"
grep -q '/usr/libexec/audiowrt/config-save' "$script"
grep -q 'save_begin network' "$script"
grep -q 'network.$ETH_INTERFACE.proto=' "$script"
grep -q 'ubus call network reload' "$script"

# The unified LuCI page keeps Ethernet and Wi-Fi together in a compact responsive grid.
grep -q '^  DEPENDS:=.*+audiowrt-network-client.*+audiowrt-wifi-client' "$luci_makefile"
grep -q '"title": "Network Client"' "$menu"
grep -q "L.resource(connected ? 'icons/ethernet.svg' : 'icons/ethernet_disabled.svg')" "$ui"
grep -q "icons/signal-075-100.svg" "$ui"
grep -q 'grid-template-columns:repeat(auto-fit,minmax' "$ui"
grep -q "_('Ethernet configuration')" "$ui"
grep -q "_('Wi-Fi configuration')" "$ui"
grep -q "_('Active route')" "$ui"
grep -q "_('RX')" "$ui"
grep -q "_('TX')" "$ui"

# Existing images can keep selecting the old LuCI package name during migration.
grep -q '+luci-app-audiowrt-network-client' "$compat"
[ ! -e "$repo_root/luci-app-audiowrt-wifi-client/htdocs/luci-static/resources/view/audiowrt-wifi-client/client.js" ]
[ ! -e "$repo_root/luci-app-audiowrt-wifi-client/root/usr/share/luci/menu.d/luci-app-audiowrt-wifi-client.json" ]

echo 'Unified AudioWRT network client package tests passed.'
