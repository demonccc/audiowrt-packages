#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

core_config="$repo_root/audiowrt-core/files/audiowrt.config"
core_firstboot="$repo_root/audiowrt-core/files/audiowrt-core-firstboot"
provision="$repo_root/audiowrt-provisioning/files/audiowrt-provision"
firstboot="$repo_root/audiowrt-provisioning/files/audiowrt-provisioning-firstboot"
storage="$repo_root/audiowrt-storage/files/audiowrt-storage"
root_router="$repo_root/audiowrt-provisioning/files/audiowrt-root.cgi"
setup_ssid="$repo_root/audiowrt-provisioning/files/audiowrt-setup-ssid"
provisioning_makefile="$repo_root/audiowrt-provisioning/Makefile"

if grep -Eq 'option (device_name|wifi_ssid)|config storage' "$core_config"; then
    echo 'ERROR: audiowrt core config duplicates OpenWrt-owned identity, Wi-Fi, or storage state.' >&2
    exit 1
fi

grep -q "name='audiowrt'" "$core_firstboot"
grep -q '/proc/sys/kernel/hostname' "$core_firstboot"
grep -q 'system.@system\[0\].hostname' "$provision"
grep -q '/usr/sbin/audiowrt-wifi-client connect' "$provision"
grep -q '/usr/sbin/audiowrt-wifi-client setup-start' "$firstboot"
grep -q 'Failed to start provisioning AP' "$firstboot"
grep -q '/usr/libexec/audiowrt/setup-ssid' "$firstboot"
grep -q "index_page='cgi-bin/audiowrt-root'" "$firstboot"
grep -q '/etc/init.d/uhttpd restart' "$firstboot"
grep -q 'audiowrt.local' "$root_router"
grep -q 'SERVER_ADDR' "$root_router"
grep -q "provisioning.*=.*'1'" "$root_router"
grep -q "redirect '/cgi-bin/luci/'" "$root_router"
grep -q 'tail -c 4' "$setup_ssid"
grep -q '+audiowrt-hostapd' "$provisioning_makefile"
grep -q '+audiowrt-udhcpd' "$provisioning_makefile"
grep -q 'audiowrt-storage.main' "$storage"

# Minimal images intentionally omit /etc/config/dhcp. Any DHCP commit in
# firstboot must remain inside the guarded "file exists" block.
if grep -q '^uci -q commit dhcp$' "$firstboot"; then
    echo 'ERROR: minimal first boot must not unconditionally commit an absent DHCP UCI package.' >&2
    exit 1
fi
grep -q 'uci -q commit dhcp || true' "$firstboot"

# Check active runtime code only. The uci-defaults migration intentionally reads
# and deletes the former keys so existing installations can be upgraded safely.
if grep -Eq 'audiowrt\.main\.wifi_ssid\|audiowrt\.main\.device_name\|audiowrt\.storage' \
    "$provision" "$firstboot" "$storage"; then
    echo 'ERROR: distribution packages still reference deprecated duplicated UCI state.' >&2
    exit 1
fi

printf 'Provisioning ownership tests passed.\n'
