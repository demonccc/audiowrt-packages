#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

core_config="$repo_root/audiowrt-core/files/audiowrt.config"
provisioning="$repo_root/audiowrt-provisioning"
storage="$repo_root/audiowrt-storage/files/audiowrt-storage"
menu_filter="$repo_root/luci-app-audiowrt-core/root/usr/share/luci/menu.d/zz-audiowrt-network-filter.json"

if grep -Eq 'device_name|wifi_ssid|^config storage' "$core_config"; then
    echo 'ERROR: AudioWRT core config duplicates hostname, Wi-Fi, or storage state.' >&2
    exit 1
fi
grep -q 'system.@system\[0\].hostname' "$repo_root/audiowrt-core/files/audiowrt-core-firstboot"

grep -q '+audiowrt-wifi-client' "$provisioning/Makefile"
grep -q '/usr/sbin/audiowrt-wifi-client' "$provisioning/files/audiowrt-provisioning-firstboot"
grep -q '/usr/sbin/audiowrt-wifi-client connect' "$provisioning/files/audiowrt-provision"
grep -q '/bin/busybox passwd root' "$provisioning/files/audiowrt-provision.cgi"
grep -q 'audiowrt-scan.cgi' "$provisioning/Makefile"
grep -q 'audiowrt-radios.cgi' "$provisioning/Makefile"
grep -q 'bssid' "$provisioning/files/audiowrt-provision.cgi"
grep -q 'alternate_radio' "$provisioning/files/audiowrt-provision"

for label in 'Welcome' 'Select Wi-Fi' 'Wi-Fi password' 'Administrator password' 'Connect' 'Done'; do
    grep -q "$label" "$provisioning/files/audiowrt.html"
done
grep -q 'data-toggle="wifi-key"' "$provisioning/files/audiowrt.html"
grep -q 'data-toggle="admin-password"' "$provisioning/files/audiowrt.html"
if grep -q 'data-toggle="admin-confirm"' "$provisioning/files/audiowrt.html"; then
    echo 'ERROR: administrator password confirmation must not expose a second Show button.' >&2
    exit 1
fi
grep -q 'Passwords match' "$provisioning/files/audiowrt.html"
grep -q 'groupNetworks' "$provisioning/files/audiowrt.html"

# Storage remains supported but is not required by the 8 MB core.
grep -q 'audiowrt-storage.main' "$storage"
if grep -q 'audiowrt\.storage' "$storage"; then
    echo 'ERROR: storage runtime still writes the legacy audiowrt.storage section.' >&2
    exit 1
fi
if grep -q 'admin/network/diagnostics' "$menu_filter"; then
    echo 'ERROR: Diagnostics must remain visible; it should not be overridden by the hidden-menu file.' >&2
    exit 1
fi
grep -q 'admin/network/wireless' "$menu_filter"

[ ! -e "$repo_root/luci-app-audiowrt-core/htdocs/luci-static/resources/view/audiowrt-core/network.js" ]
[ ! -e "$repo_root/luci-app-audiowrt-core/htdocs/luci-static/resources/view/audiowrt-core/system.js" ]

echo 'AudioWRT appliance integration tests passed.'
