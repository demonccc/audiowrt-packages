#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bluez="$repo_root/audiowrt-bluez/Makefile"
sbc="$repo_root/audiowrt-sbc/Makefile"
bluealsa="$repo_root/bluez-alsa/Makefile"
bluetooth="$repo_root/audiowrt-bluetooth/Makefile"
wrapper="$repo_root/audiowrt-bluetooth/files/audiowrt-bluetooth"

# Generic OpenWrt BlueZ pulls tools, readline/ncurses and libical. AudioWRT
# keeps bluetoothd, libbluetooth, A2DP/AVRCP and Bluetooth MIDI only.
for option in --disable-client --disable-tools --disable-monitor --disable-obex --disable-network --disable-hid --disable-hog --enable-library --enable-midi; do
    grep -q -- "$option" "$bluez"
done
if grep -q -- '--disable-midi' "$bluez"; then
    echo 'ERROR: Bluetooth MIDI must remain enabled in the measured baseline.' >&2
    exit 1
fi
grep -q 'DEPENDS:=.*+alsa-lib' "$bluez"
if grep -Eq 'DEPENDS:=.*(libreadline|libncurses|libical|bluez-utils|\+bluez-libs)' "$bluez"; then
    echo 'ERROR: minimal BlueZ reintroduced generic BlueZ/CLI/profile dependencies.' >&2
    exit 1
fi
grep -q '^define Package/audiowrt-bluez-libs$' "$bluez"
grep -q 'libbluetooth.so' "$bluez"

# Generic OpenWrt sbc depends on libsndfile, which pulls multiple audio codecs.
# The AudioWRT package must ship only the SBC shared library.
if grep -Eq 'DEPENDS:=.*libsndfile' "$sbc"; then
    echo 'ERROR: minimal SBC must not depend on libsndfile.' >&2
    exit 1
fi
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
grep -q '/usr/bin/audiowrt-btctl' "$wrapper"
if grep -Eq '\b(bluetoothctl|hciconfig)\b' "$wrapper"; then
    echo 'ERROR: Bluetooth wrapper still requires generic BlueZ CLI utilities.' >&2
    exit 1
fi

echo 'Minimal Bluetooth + MIDI dependency tests passed.'
