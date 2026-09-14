#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
alsa="$repo_root/audiowrt-minimal-alsa/Makefile"
mbedtls="$repo_root/audiowrt-minimal-mbedtls/Makefile"
bluetooth="$repo_root/audiowrt-kmod-bluetooth/Makefile"
bluetooth_integration="$repo_root/audiowrt-bluetooth/Makefile"

# ALSA keeps every interface and PCM plugin used by the AudioWRT USB,
# USB Audio and BlueALSA paths, but drops MIDI and general-purpose features.
for keep in '--with-pcm-plugins=linear,route,rate,plug,dmix,ioplug' '--with-ctl-plugins=ext'; do
	grep -q -- "$keep" "$alsa"
done
for drop in '--disable-ucm' '--disable-topology' '--disable-alisp' '--disable-rawmidi' '--disable-seq' '--disable-hwdep'; do
	grep -q -- "$drop" "$alsa"
done
if grep -q 'libatopology' "$alsa"; then
	echo 'ERROR: minimal ALSA must not stage or install libatopology.' >&2
	exit 1
fi
grep -q 'libasound.so' "$alsa"
grep -q '^define Package/audiowrt-minimal-alsa$' "$alsa"
grep -q '^  PROVIDES:=alsa-lib$' "$alsa"
! grep -q '^  CONFLICTS:=' "$alsa"

# The sound kernel capability is required in the firmware, but ALSA itself
# does not compile against the OpenWrt kernel. Keep it out of the source build
# graph so compiling ALSA and BlueALSA cannot rebuild the release kernel.
grep -q '^  EXTRA_DEPENDS:=kmod-sound-core (>=0)$' "$alsa"
if awk '/^define Package\/audiowrt-minimal-alsa$/{inside=1; next} /^endef$/{inside=0} inside && /^  DEPENDS:=/ && /kmod-sound-core/{found=1} END{exit found ? 0 : 1}' "$alsa"; then
	echo 'ERROR: ALSA runtime kmod must not participate in source dependency expansion.' >&2
	exit 1
fi

# Mbed TLS preserves the modern TLS and WPA crypto contract. Only unused
# curves and TLS-PSK modes are removed from the shared implementation.
for keep in \
	MBEDTLS_SSL_PROTO_TLS1_2 \
	MBEDTLS_SSL_PROTO_TLS1_3 \
	MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_EPHEMERAL_ENABLED \
	MBEDTLS_ECP_DP_SECP256R1_ENABLED \
	MBEDTLS_ECP_DP_SECP384R1_ENABLED \
	MBEDTLS_ECP_DP_CURVE25519_ENABLED \
	MBEDTLS_CMAC_C \
	MBEDTLS_DES_C \
	MBEDTLS_NIST_KW_C; do
	awk '/^MBEDTLS_SET_OPTIONS:=/{inside=1} inside && $0 ~ token {found=1} /^$/{if (inside) exit} END{exit found ? 0 : 1}' token="$keep" "$mbedtls"
done
grep -q '^define Package/audiowrt-minimal-mbedtls$' "$mbedtls"
grep -q '^  PROVIDES:=libmbedtls libmbedtls21$' "$mbedtls"
! grep -q '^  CONFLICTS:=' "$mbedtls"

grep -q '^AUDIOWRT_BLUETOOTH_PROVIDES:=kmod-bluetooth kmod-btusb kmod-btmtk$' "$bluetooth"
grep -q '^ifneq ($(DUMP),1)$' "$bluetooth"
grep -q '^  PROVIDES:=$(AUDIOWRT_BLUETOOTH_PROVIDES)$' "$bluetooth"
! grep -q '^  CONFLICTS:=' "$bluetooth"
grep -q '^define Package/kmod-audiowrt-bluetooth/extra_provides$' "$bluetooth"
for module in crc16.ko ecdh_generic.ko kpp.ko usbcore.ko; do
    grep -Fq "$module" "$bluetooth"
done
if grep -Eq 'rfcomm\.ko|bnep\.ko|hidp\.ko|kmod-hid' "$bluetooth"; then
	echo 'ERROR: minimal Bluetooth kernel package includes excluded profiles.' >&2
	exit 1
fi

# Kernel capabilities are firmware runtime requirements, not build inputs for
# this file-only integration package. Keeping them in EXTRA_DEPENDS avoids
# OpenWrt expanding both official and minimal providers into a Kconfig cycle.
grep -q '^  EXTRA_DEPENDS:=kmod-bluetooth (>=0), kmod-btusb (>=0)$' "$bluetooth_integration"
if awk '/^define Package\/audiowrt-bluetooth$/{inside=1; next} /^endef$/{inside=0} inside && /^  DEPENDS:=/ && /kmod-(bluetooth|btusb)/{found=1} END{exit found ? 0 : 1}' "$bluetooth_integration"; then
	echo 'ERROR: Bluetooth runtime kmods must not participate in Kconfig dependency expansion.' >&2
	exit 1
fi
for drop in \
	MBEDTLS_ECP_DP_SECP521R1_ENABLED \
	MBEDTLS_ECP_DP_SECP256K1_ENABLED \
	MBEDTLS_KEY_EXCHANGE_PSK_ENABLED \
	MBEDTLS_KEY_EXCHANGE_ECDHE_PSK_ENABLED \
	MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_PSK_ENABLED \
	MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_PSK_EPHEMERAL_ENABLED; do
	awk '/^MBEDTLS_UNSET_OPTIONS:=/{inside=1} inside && $0 ~ token {found=1} /^$/{if (inside) exit} END{exit found ? 0 : 1}' token="$drop" "$mbedtls"
done

echo 'Minimal runtime-library contracts passed.'
