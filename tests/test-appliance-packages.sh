#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

provisioning="$repo_root/audiowrt-provisioning"
storage="$repo_root/audiowrt-storage/files/audiowrt-storage"
menu_filter="$repo_root/luci-app-audiowrt-core/root/usr/share/luci/menu.d/zz-audiowrt-network-filter.json"

if [ -e "$repo_root/audiowrt-core/files/audiowrt.config" ] ||
   [ -e "$repo_root/audiowrt-core/files/audiowrt-core-firstboot" ]; then
    echo 'ERROR: AudioWRT core still carries persistent provisioning state.' >&2
    exit 1
fi
if grep -Eq '/etc/config|uci-defaults|audiowrt\.config|audiowrt-core-firstboot' "$repo_root/audiowrt-core/Makefile"; then
    echo 'ERROR: AudioWRT core package still installs persistent provisioning state.' >&2
    exit 1
fi

grep -q '+audiowrt-wifi-client' "$provisioning/Makefile"
grep -q 'provisioning auto' "$provisioning/files/provision-supervisor"
grep -q 'audiowrt_connected' "$provisioning/files/audiowrtctl"
grep -q 'wifi-runtime' "$repo_root/audiowrt-wifi-client/Makefile"
grep -q '+luci-app-audiowrt-network-client' "$repo_root/luci-app-audiowrt-wifi-client/Makefile"
grep -q '"title": "Network Client"' "$repo_root/luci-app-audiowrt-network-client/root/usr/share/luci/menu.d/luci-app-audiowrt-network-client.json"
if grep -Eq 'uci-defaults|uci -q commit|rm -f.*/etc/' "$provisioning/files/audiowrt-provisioning.init"; then
    echo 'ERROR: provisioning init must not persist or migrate configuration.' >&2
    exit 1
fi
grep -q '/usr/sbin/audiowrt-wifi-client connect' "$provisioning/files/audiowrt-provision"
grep -q '/bin/busybox passwd root' "$provisioning/files/audiowrt-provision.cgi"
grep -q 'audiowrt-scan.cgi' "$provisioning/Makefile"
grep -q 'audiowrt-radios.cgi' "$provisioning/Makefile"
grep -q 'audiowrt-provisioning.init' "$provisioning/Makefile"
grep -q 'S99audiowrt-provisioning' "$provisioning/Makefile"
if grep -q 'provisioning_initialized' "$provisioning/files/audiowrt-provisioning.init"; then
    echo 'ERROR: provisioning init must not depend on a persistent initialized flag.' >&2
    exit 1
fi
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

[ ! -e "$storage" ]
if grep -q 'admin/network/diagnostics' "$menu_filter"; then
    echo 'ERROR: Diagnostics must remain visible; it should not be overridden by the hidden-menu file.' >&2
    exit 1
fi
grep -q 'admin/network/wireless' "$menu_filter"

[ ! -e "$repo_root/luci-app-audiowrt-core/htdocs/luci-static/resources/view/audiowrt-core/network.js" ]
[ ! -e "$repo_root/luci-app-audiowrt-core/htdocs/luci-static/resources/view/audiowrt-core/system.js" ]

# Optional audio services are standalone modules. The obsolete shared
# extensions manager and LuCI Extensions page must not return.
[ ! -e "$repo_root/audiowrt-extensions" ]
[ ! -e "$repo_root/luci-app-audiowrt/htdocs/luci-static/resources/view/audiowrt/extensions.js" ]
! grep -q 'audiowrt-extensions' "$repo_root/audiowrt-mpd/Makefile"
! grep -q 'audiowrt-extensions' "$repo_root/audiowrt-airplay/Makefile"
! grep -q 'audiowrt-extensions' "$repo_root/audiowrt-spotify/Makefile"
grep -q '/usr/libexec/audiowrt/mpd configure' "$repo_root/audiowrt-mpd/Makefile"
grep -q '/usr/libexec/audiowrt/airplay configure' "$repo_root/audiowrt-airplay/Makefile"
grep -q '/usr/libexec/audiowrt/spotify configure' "$repo_root/audiowrt-spotify/Makefile"
grep -q 'configure-settings' "$repo_root/audiowrt-config/Makefile"
! grep -q 'admin/audiowrt/extensions' "$repo_root/luci-app-audiowrt/root/usr/share/luci/menu.d/luci-app-audiowrt.json"
! grep -q 'audiowrt-extensions' "$repo_root/luci-app-audiowrt/root/usr/share/rpcd/acl.d/luci-app-audiowrt.json"

echo 'AudioWRT appliance integration tests passed.'
