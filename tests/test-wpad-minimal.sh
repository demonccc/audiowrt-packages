#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makefile="$repo_root/audiowrt-wpad/Makefile"
hostapd_config="$repo_root/audiowrt-wpad/files/hostapd-audiowrt.config"
supplicant_config="$repo_root/audiowrt-wpad/files/wpa_supplicant-audiowrt.config"

# Stable package/source contract.
grep -q '^AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/base/network/services/hostapd/Makefile$' "$makefile"
! grep -q '^PKG_VERSION:=' "$makefile"
grep -q '^  PROVIDES:=hostapd wpa-supplicant$' "$makefile"

# One multicall ELF, two standard OpenWrt entry points and both ucode adapters.
grep -q 'MULTICALL=1' "$makefile"
grep -q 'hostapd_multi.a' "$makefile"
grep -q 'wpa_supplicant_multi.a' "$makefile"
grep -q 'multicall.c' "$makefile"
grep -q '$(INSTALL_BIN) $(PKG_BUILD_DIR)/wpad $(1)/usr/sbin/' "$makefile"
grep -q '$(LN) wpad $(1)/usr/sbin/hostapd' "$makefile"
grep -q '$(LN) wpad $(1)/usr/sbin/wpa_supplicant' "$makefile"
grep -q 'hostapd.uc' "$makefile"
grep -q 'wpa_supplicant.uc' "$makefile"

# Keep TLS selection centralized in the multicall recipe rather than duplicated
# independently in each side-specific config.
grep -q 'CONFIG_TLS=' "$makefile"
! grep -q '^CONFIG_TLS=' "$hostapd_config"
! grep -q '^CONFIG_TLS=' "$supplicant_config"

# The provisioning AP stays intentionally minimal/open.
for keep in \
    CONFIG_DRIVER_NL80211=y \
    CONFIG_IEEE80211N=y \
    CONFIG_ACS=y \
    CONFIG_UBUS=y; do
    grep -qx "$keep" "$hostapd_config"
done

for drop in \
    CONFIG_DRIVER_WIRED \
    CONFIG_IEEE80211AC \
    CONFIG_IEEE80211AX \
    CONFIG_IEEE80211BE \
    CONFIG_EAP \
    CONFIG_WPS \
    CONFIG_IEEE80211R \
    CONFIG_SAE \
    CONFIG_OWE \
    CONFIG_DPP \
    CONFIG_MBO \
    CONFIG_INTERWORKING \
    CONFIG_HS20; do
    if grep -q "^$drop" "$hostapd_config"; then
        echo "ERROR: excluded provisioning AP feature present: $drop" >&2
        exit 1
    fi
done

# The station side stays within AudioWRT's WPA2/WPA3 Personal scope.
for keep in \
    CONFIG_DRIVER_NL80211=y \
    CONFIG_CTRL_IFACE=y \
    CONFIG_BACKEND=file \
    CONFIG_IEEE80211W=y \
    CONFIG_SAE=y \
    CONFIG_UBUS=y; do
    grep -qx "$keep" "$supplicant_config"
done

for drop in \
    CONFIG_DRIVER_WIRED \
    CONFIG_IEEE8021X_EAPOL \
    CONFIG_EAP_ \
    CONFIG_WPS \
    CONFIG_AP= \
    CONFIG_P2P \
    CONFIG_MESH \
    CONFIG_INTERWORKING \
    CONFIG_HS20 \
    CONFIG_FILS \
    CONFIG_IBSS_RSN \
    CONFIG_DPP \
    CONFIG_OWE; do
    if grep -q "^$drop" "$supplicant_config"; then
        echo "ERROR: excluded station feature present: $drop" >&2
        exit 1
    fi
done

# Do not regress to two independent hostap executables.
test ! -e "$repo_root/audiowrt-wpa-supplicant/Makefile"
test ! -e "$repo_root/audiowrt-hostapd/Makefile"

echo 'Minimal AudioWRT multicall wpad contract passed.'
