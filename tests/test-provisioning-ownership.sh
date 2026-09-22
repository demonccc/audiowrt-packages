#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

provision="$repo_root/audiowrt-provisioning/files/audiowrt-provision"
provision_cgi="$repo_root/audiowrt-provisioning/files/audiowrt-provision.cgi"
init="$repo_root/audiowrt-provisioning/files/audiowrt-provisioning.init"
ctl="$repo_root/audiowrt-provisioning/files/audiowrtctl"
status_cgi="$repo_root/audiowrt-provisioning/files/audiowrt-status.cgi"
storage="$repo_root/audiowrt-storage/files/audiowrt-storage"
root_router="$repo_root/audiowrt-provisioning/files/audiowrt-root.cgi"
setup_ssid="$repo_root/audiowrt-provisioning/files/audiowrt-setup-ssid"
provisioning_makefile="$repo_root/audiowrt-provisioning/Makefile"
runtime="$repo_root/audiowrt-wifi-client/files/audiowrt-wifi-runtime"

if [ -e "$repo_root/audiowrt-core/files/audiowrt.config" ] ||
   [ -e "$repo_root/audiowrt-core/files/audiowrt-core-firstboot" ]; then
    echo 'ERROR: audiowrt core still carries persistent provisioning state.' >&2
    exit 1
fi

grep -q "AUDIOWRT_SETUP_IP='192.168.77.1'" "$runtime"
grep -q "AUDIOWRT_SETUP_SSID='AudioWRT-Setup'" "$runtime"
grep -q 'AUDIOWRT_SETUP_TIMEOUT=45' "$runtime"
grep -q 'system.@system\[0\].hostname' "$provision"
grep -q 'AUDIOWRT_WIFI_PERSIST=0' "$provision"
grep -q 'audiowrt-wifi-client commit-client' "$provision"
grep -q 'network.audiowrt_setup.ipaddr' "$provision"
grep -q 'provisioning auto' "$init"
grep -q '^has_persistent_wifi_client()' "$ctl"
grep -q '^has_lan_dhcp()' "$ctl"
grep -q 'persistent Wi-Fi client configuration exists' "$ctl"
grep -q 'LAN DHCP lease detected' "$ctl"
grep -q 'audiowrt_first_radio' "$ctl"
if grep -Eq 'uci-defaults|uci -q commit|rm -f.*/etc/' "$init"; then
    echo 'ERROR: provisioning init must not migrate or persist configuration.' >&2
    exit 1
fi
if [ -e "$repo_root/audiowrt-provisioning/files/audiowrt-provisioning-firstboot" ]; then
    echo 'ERROR: provisioning package still carries a persistent firstboot migration.' >&2
    exit 1
fi
if grep -q 'uci-defaults' "$provisioning_makefile"; then
    echo 'ERROR: provisioning package must not install a persistent firstboot migration.' >&2
    exit 1
fi
grep -q 'SERVER_ADDR' "$root_router"
grep -q 'setup_ip' "$root_router"
grep -q "redirect '/audiowrt.html'" "$root_router"
grep -q "redirect '/cgi-bin/luci/'" "$root_router"
grep -q 'SERVER_ADDR' "$provision_cgi"
grep -q 'network.interface.audiowrt_setup status' "$status_cgi"
grep -q 'network.interface.audiowrt_wifi status' "$status_cgi"
grep -q 'setup-stop' "$status_cgi"
grep -q 'tail -c 4' "$setup_ssid"
grep -q '+hostapd' "$provisioning_makefile"
grep -q '+audiowrt-udhcpd' "$provisioning_makefile"
grep -q 'audiowrt-storage.main' "$storage"

# Provisioning must not depend on removed persistent state booleans.
for file in "$provision" "$provision_cgi" "$init" "$ctl" "$status_cgi" "$root_router"; do
    if grep -q 'audiowrt\.main\.provisioning' "$file"; then
        echo "ERROR: active provisioning path still depends on persistent provisioning state: $file" >&2
        exit 1
    fi
done

# Exercise the exact DHCP parser with both a real lease and an empty lease
# list. Carrier state is intentionally irrelevant to this decision.
eval "$(sed -n '/^has_lan_dhcp()/,/^}/p' "$ctl")"
ubus() {
    case "${MOCK_LAN_STATUS:-}" in
        with-lease)
            cat <<'JSON'
{
    "up": true,
    "proto": "dhcp",
    "ipv4-address": [ { "address": "192.168.1.138", "mask": 24 } ]
}
JSON
            ;;
        without-lease)
            cat <<'JSON'
{
    "up": false,
    "proto": "dhcp",
    "ipv4-address": [ ]
}
JSON
            ;;
    esac
}
MOCK_LAN_STATUS=with-lease has_lan_dhcp
if MOCK_LAN_STATUS=without-lease has_lan_dhcp; then
    echo 'ERROR: empty DHCP status was treated as a lease.' >&2
    exit 1
fi

# Check active runtime code only.
if grep -Eq 'audiowrt\.main\.wifi_ssid\|audiowrt\.main\.device_name\|audiowrt\.storage' \
    "$provision" "$storage"; then
    echo 'ERROR: distribution packages still reference deprecated duplicated UCI state.' >&2
    exit 1
fi

printf 'Provisioning ownership tests passed.\n'
