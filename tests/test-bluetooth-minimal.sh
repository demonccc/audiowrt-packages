#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bluez="$repo_root/audiowrt-bluez/Makefile"
bluez_vcp_patch="$repo_root/audiowrt-bluez/releases/25.12/patches/900-transport-fix-build-with-vcp-disabled.patch"
sbc="$repo_root/audiowrt-sbc/Makefile"
bluealsa="$repo_root/bluez-alsa/Makefile"
bluetooth="$repo_root/audiowrt-bluetooth/Makefile"
wrapper="$repo_root/audiowrt-bluetooth/files/audiowrt-bluetooth"

# AudioWRT keeps bluetoothd, libbluetooth and A2DP/AVRCP only. The package
# inherits its source identity and canonical OpenWrt patches from the selected
# release; this test validates only the AudioWRT feature delta.
for option in --disable-client --disable-tools --disable-monitor --disable-obex --disable-network --disable-hid --disable-hog --enable-library --disable-midi; do
    grep -q -- "$option" "$bluez"
done
grep -q 'DEPENDS:=.*+alsa-lib' "$bluez"
if grep -q 'kmod-sound-seq' "$bluez"; then
    echo 'ERROR: ALSA Sequencer must not be pulled without a complete MIDI feature.' >&2
    exit 1
fi
if grep -Eq 'DEPENDS:=.*(libreadline|libncurses|libical|bluez-utils|\+bluez-libs)' "$bluez"; then
    echo 'ERROR: minimal BlueZ reintroduced generic BlueZ/CLI/profile dependencies.' >&2
    exit 1
fi
grep -q '^define Package/audiowrt-bluez-libs$' "$bluez"
grep -q 'libbluetooth.so' "$bluez"

# OpenWrt 25.12's BlueZ currently needs an AudioWRT compatibility delta when
# VCP is disabled. Keep it release-scoped so other OpenWrt families never
# receive a patch that was written for a different BlueZ version.
grep -q -- '--disable-vcp' "$bluez"
test -f "$bluez_vcp_patch"
grep -q 'c6dcf6b714501768ab7ea293e75d945be0eec188' "$bluez_vcp_patch"
grep -q '#ifdef HAVE_VCP' "$bluez_vcp_patch"
grep -q 'return -ENODEV' "$bluez_vcp_patch"

# Generic OpenWrt sbc depends on libsndfile for the upstream tester, which pulls
# multiple audio codecs. AudioWRT disables the tester and ships only libsbc.
if grep -Eq 'DEPENDS:=.*libsndfile' "$sbc"; then
    echo 'ERROR: minimal SBC must not depend on libsndfile.' >&2
    exit 1
fi
grep -q -- '--disable-tester' "$sbc" || {
    echo 'ERROR: minimal SBC must disable the libsndfile-backed tester.' >&2
    exit 1
}
if grep -q 'usr/bin' "$sbc"; then
    echo 'ERROR: minimal SBC must not install command-line utilities.' >&2
    exit 1
fi
grep -q 'libsbc.so' "$sbc"

# BlueALSA and the product wrapper must use only the minimal AudioWRT packages.
grep -q 'DEPENDS:=.*+audiowrt-bluez.*+audiowrt-bluez-libs.*+glib2.*+audiowrt-sbc' "$bluealsa"
if grep -Eq 'DEPENDS:=.*(\+bluez-daemon|\+bluez-libs|\+sbc([[:space:]]|$))' "$bluealsa"; then
    echo 'ERROR: BlueALSA still depends on the generic BlueZ/SBC runtime.' >&2
    exit 1
fi
grep -q 'DEPENDS:=.*+audiowrt-bluez.*+audiowrt-btctl' "$bluetooth"
grep -q '^  EXTRA_DEPENDS:=kmod-bluetooth (>=0), kmod-btusb (>=0)$' "$bluetooth"
if grep -q 'DEPENDS:=.*+kmod-bluetooth.*+kmod-btusb' "$bluetooth"; then
    echo 'ERROR: Bluetooth runtime kmods must not participate in Kconfig dependency expansion.' >&2
    exit 1
fi
grep -q '/usr/bin/audiowrt-btctl' "$wrapper"
if grep -Eq '\b(bluetoothctl|hciconfig)\b' "$wrapper"; then
    echo 'ERROR: Bluetooth wrapper still requires generic BlueZ CLI utilities.' >&2
    exit 1
fi

echo 'Minimal Bluetooth audio dependency tests passed.'
