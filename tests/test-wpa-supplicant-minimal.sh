#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makefile="$repo_root/audiowrt-wpa-supplicant/Makefile"
config="$repo_root/audiowrt-wpa-supplicant/files/wpa_supplicant-audiowrt.config"

grep -q '^AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/base/network/services/hostapd/Makefile$' "$makefile"
grep -q '^  PROVIDES:=wpa-supplicant$' "$makefile"
grep -q '+libmbedtls' "$makefile"
grep -q 'CONFIG_TLS=mbedtls' "$makefile"
grep -q 'CONFIG_SAE=y' "$makefile"
grep -q 'wpa_supplicant.uc' "$makefile"
grep -q 'wpa_supplicant$' "$makefile"

if grep -q 'wpa-supplicant-mbedtls' "$makefile"; then
    echo 'ERROR: AudioWRT WPA package must compile its own client-only supplicant.' >&2
    exit 1
fi
if grep -Eq 'hostapd$|wpad$|wpa_cli$|eapol_test$' "$makefile"; then
    echo 'ERROR: minimal WPA package must build only wpa_supplicant.' >&2
    exit 1
fi

for keep in     CONFIG_DRIVER_NL80211=y     CONFIG_CTRL_IFACE=y     CONFIG_IEEE80211W=y     CONFIG_SAE=y     CONFIG_UBUS=y     CONFIG_NO_STDOUT_DEBUG=y     CONFIG_NO_CONFIG_WRITE=y     CONFIG_NO_CONFIG_BLOBS=y; do
    grep -qx "$keep" "$config"
done

for drop in     CONFIG_IEEE8021X_EAPOL     CONFIG_EAP_     CONFIG_WPS     CONFIG_AP=     CONFIG_P2P     CONFIG_MESH     CONFIG_INTERWORKING     CONFIG_HS20     CONFIG_FILS     CONFIG_IBSS_RSN     CONFIG_DPP     CONFIG_OWE; do
    if grep -q "^$drop" "$config"; then
        echo "ERROR: excluded WPA feature present: $drop" >&2
        exit 1
    fi
done

echo 'Minimal WPA2/WPA3 station supplicant contract passed.'
