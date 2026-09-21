#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

core_config="$repo_root/audiowrt-core/files/audiowrt.config"
core_firstboot="$repo_root/audiowrt-core/files/audiowrt-core-firstboot"
provision="$repo_root/audiowrt-provisioning/files/audiowrt-provision"
provision_cgi="$repo_root/audiowrt-provisioning/files/audiowrt-provision.cgi"
firstboot="$repo_root/audiowrt-provisioning/files/audiowrt-provisioning-firstboot"
init="$repo_root/audiowrt-provisioning/files/audiowrt-provisioning.init"
ctl="$repo_root/audiowrt-provisioning/files/audiowrtctl"
status_cgi="$repo_root/audiowrt-provisioning/files/audiowrt-status.cgi"
storage="$repo_root/audiowrt-storage/files/audiowrt-storage"
root_router="$repo_root/audiowrt-provisioning/files/audiowrt-root.cgi"
setup_ssid="$repo_root/audiowrt-provisioning/files/audiowrt-setup-ssid"
provisioning_makefile="$repo_root/audiowrt-provisioning/Makefile"

if grep -Eq 'option (device_name|wifi_ssid|provisioning|provisioning_initialized)|config storage' "$core_config"; then
    echo 'ERROR: audiowrt core config contains duplicated identity, connectivity, storage, or provisioning state.' >&2
    exit 1
fi

grep -q "name='audiowrt'" "$core_firstboot"
grep -q '/proc/sys/kernel/hostname' "$core_firstboot"
grep -q 'system.@system\[0\].hostname' "$provision"
grep -q 'AUDIOWRT_WIFI_PERSIST=0' "$provision"
grep -q 'audiowrt-wifi-client commit-client' "$provision"
grep -q 'network.audiowrt_setup.ipaddr' "$provision"
grep -q 'provisioning auto' "$init"
grep -q '^has_persistent_wifi_client()' "$ctl"
grep -q '^has_ethernet_link()' "$ctl"
grep -q '^swconfig_lan_link()' "$ctl"
grep -q '/sys/class/net/.*/carrier' "$ctl"
grep -q 'persistent Wi-Fi client configuration exists' "$ctl"
grep -q 'Ethernet carrier detected' "$ctl"
grep -q "index_page='cgi-bin/audiowrt-root'" "$firstboot"
grep -q '/etc/init.d/uhttpd restart' "$firstboot"
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

# Runtime setup must not be created by the persistent firstboot migration.
if grep -q 'audiowrt-wifi-client setup-start' "$firstboot"; then
    echo 'ERROR: firstboot must not persist or start the runtime setup AP.' >&2
    exit 1
fi

# The removed booleans are allowed only in the one-time migration that deletes
# them from older installations.
for file in "$provision" "$provision_cgi" "$init" "$ctl" "$status_cgi" "$root_router"; do
    if grep -q 'audiowrt\.main\.provisioning' "$file"; then
        echo "ERROR: active provisioning path still depends on persistent provisioning state: $file" >&2
        exit 1
    fi
done
grep -q 'delete audiowrt.main."$option"' "$firstboot"

# Minimal images intentionally omit /etc/config/dhcp. Any DHCP commit in
# firstboot must remain inside the guarded "file exists" block.
if grep -q '^uci -q commit dhcp$' "$firstboot"; then
    echo 'ERROR: minimal first boot must not unconditionally commit an absent DHCP UCI package.' >&2
    exit 1
fi
grep -q 'uci -q commit dhcp || true' "$firstboot"

# Check active runtime code only. The uci-defaults migration intentionally reads
# and deletes former keys so existing installations can be upgraded safely.
if grep -Eq 'audiowrt\.main\.wifi_ssid\|audiowrt\.main\.device_name\|audiowrt\.storage' \
    "$provision" "$firstboot" "$storage"; then
    echo 'ERROR: distribution packages still reference deprecated duplicated UCI state.' >&2
    exit 1
fi

printf 'Provisioning ownership tests passed.\n'
