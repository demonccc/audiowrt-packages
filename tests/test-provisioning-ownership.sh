#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

core_config="$repo_root/audiowrt-core/files/audiowrt.config"
core_firstboot="$repo_root/audiowrt-core/files/audiowrt-core-firstboot"
provision="$repo_root/audiowrt-provisioning/files/audiowrt-provision"
firstboot="$repo_root/audiowrt-provisioning/files/audiowrt-provisioning-firstboot"
storage="$repo_root/audiowrt-storage/files/audiowrt-storage"

if grep -Eq 'option (device_name|wifi_ssid)|config storage' "$core_config"; then
    echo 'ERROR: audiowrt core config duplicates OpenWrt-owned identity, Wi-Fi, or storage state.' >&2
    exit 1
fi

grep -q 'system.@system\[0\].hostname' "$core_firstboot"
grep -q 'system.@system\[0\].hostname' "$provision"
grep -q '/usr/sbin/audiowrt-wifi-client connect' "$provision"
grep -q '/usr/sbin/audiowrt-wifi-client setup-start' "$firstboot"
grep -q 'audiowrt-storage.main' "$storage"

# Check active runtime code only. The uci-defaults migration intentionally reads
# and deletes the former keys so existing installations can be upgraded safely.
if grep -Eq 'audiowrt\.main\.wifi_ssid\|audiowrt\.main\.device_name\|audiowrt\.storage' \
    "$provision" "$firstboot" "$storage"; then
    echo 'ERROR: distribution packages still reference deprecated duplicated UCI state.' >&2
    exit 1
fi

printf 'Provisioning ownership tests passed.\n'
