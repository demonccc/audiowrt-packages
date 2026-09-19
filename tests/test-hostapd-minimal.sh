#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makefile="$repo_root/audiowrt-hostapd/Makefile"
config="$repo_root/audiowrt-hostapd/files/hostapd-audiowrt.config"

grep -q '^AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/base/network/services/hostapd/Makefile$' "$makefile"
grep -q '^  PROVIDES:=hostapd$' "$makefile"
grep -q 'hostapd.uc' "$makefile"
grep -q $'\thostapd$' "$makefile"
grep -q 'CONFIG_UCODE=y' "$makefile"
grep -q 'CONFIG_APUP=y' "$makefile"

for keep in \
    CONFIG_DRIVER_NL80211=y \
    CONFIG_IEEE80211N=y \
    CONFIG_UBUS=y \
    CONFIG_DEBUG_SYSLOG=y \
    CONFIG_DEBUG_SYSLOG_FACILITY=LOG_DAEMON \
    CONFIG_NO_ACCOUNTING=y \
    CONFIG_NO_RADIUS=y \
    CONFIG_NO_VLAN=y \
    CONFIG_NO_DUMP_STATE=y \
    CONFIG_NO_STDOUT_DEBUG=y \
    CONFIG_TLS=none; do
    grep -qx "$keep" "$config"
done

for drop in \
    CONFIG_DRIVER_WIRED \
    CONFIG_IEEE80211AC \
    CONFIG_IEEE80211AX \
    CONFIG_IEEE80211BE \
    CONFIG_ACS \
    CONFIG_EAP \
    CONFIG_WPS \
    CONFIG_IEEE80211R \
    CONFIG_SAE \
    CONFIG_OWE \
    CONFIG_DPP \
    CONFIG_MBO \
    CONFIG_INTERWORKING \
    CONFIG_HS20; do
    if grep -q "^$drop" "$config"; then
        echo "ERROR: excluded hostapd feature present: $drop" >&2
        exit 1
    fi
done

if grep -Eq '\+lib(mbedtls|openssl|wolfssl)' "$makefile"; then
    echo 'ERROR: open provisioning hostapd must not pull an external TLS stack.' >&2
    exit 1
fi

echo 'Minimal open provisioning hostapd contract passed.'
