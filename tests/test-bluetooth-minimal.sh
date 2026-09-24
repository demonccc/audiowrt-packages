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
btctl_source="$repo_root/audiowrt-btctl/src/audiowrt-btctl.c"

# AudioWRT keeps bluetoothd and A2DP/AVRCP only. The daemon links against the
# official OpenWrt bluez-libs runtime instead of carrying a tiny library fork.
for option in --disable-client --disable-tools --disable-monitor --disable-obex --disable-network --disable-hid --disable-hog --enable-library --disable-midi; do
    grep -q -- "$option" "$bluez"
done
if grep -q 'DEPENDS:=.*+alsa-lib' "$bluez"; then
    echo 'ERROR: bluetoothd must not pull ALSA; BlueALSA owns the ALSA boundary.' >&2
    exit 1
fi
if grep -q 'kmod-sound-seq' "$bluez"; then
    echo 'ERROR: ALSA Sequencer must not be pulled without a complete MIDI feature.' >&2
    exit 1
fi
if grep -Eq 'DEPENDS:=.*(libreadline|libncurses|libical|bluez-utils)' "$bluez"; then
    echo 'ERROR: minimal BlueZ reintroduced generic BlueZ CLI/profile dependencies.' >&2
    exit 1
fi
grep -q 'DEPENDS:=.*+bluez-libs' "$bluez"
if grep -q '^define Package/audiowrt-bluez-libs$' "$bluez"; then
    echo 'ERROR: AudioWRT must reuse the official OpenWrt bluez-libs package.' >&2
    exit 1
fi

# OpenWrt 25.12's BlueZ currently needs an AudioWRT compatibility delta when
# VCP is disabled. Keep it release-scoped so other OpenWrt families never
# receive a patch that was written for a different BlueZ version.
grep -q -- '--disable-vcp' "$bluez"
grep -q -- '--localstatedir=/tmp' "$bluez"
test -f "$bluez_vcp_patch"
grep -q 'c6dcf6b714501768ab7ea293e75d945be0eec188' "$bluez_vcp_patch"
grep -q '#ifdef HAVE_VCP' "$bluez_vcp_patch"
grep -q 'return -ENODEV' "$bluez_vcp_patch"

# Keep the exact-release OpenWrt SBC source but strip tester/tools. This saves
# about 14.7 KiB in the constrained image while retaining the same libsbc ABI.
test -f "$sbc"
grep -Fq 'AUDIOWRT_DERIVED_NAME:=audiowrt-sbc' "$sbc"
grep -Fq 'AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/packages/libs/sbc/Makefile' "$sbc"
grep -q -- '--disable-tester' "$sbc"
if grep -Eq 'DEPENDS:=.*libsndfile|usr/bin' "$sbc"; then
    echo 'ERROR: minimal SBC must not pull tester/tool dependencies.' >&2
    exit 1
fi
grep -q 'libsbc.so' "$sbc"
grep -q 'DEPENDS:=.*+audiowrt-bluez.*+bluez-libs.*+glib2.*+audiowrt-sbc' "$bluealsa"
if grep -Eq 'DEPENDS:=.*(\+audiowrt-bluez-libs|\+sbc([[:space:]]|$))' "$bluealsa"; then
    echo 'ERROR: BlueALSA must use official bluez-libs and AudioWRT minimal SBC.' >&2
    exit 1
fi

# BlueALSA and the product wrapper keep only AudioWRT-specific integration code.
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
grep -Fq '#define BLUEZ_STORAGE "/tmp/lib/bluetooth"' "$btctl_source"
grep -Fq 'strcmp(argv[1], "adapters") == 0' "$btctl_source"
grep -Fq 'g_variant_lookup(props, "Address", "&s", &address);' "$btctl_source"
grep -Fq 'g_variant_lookup(props, "Alias", "&s", &alias);' "$btctl_source"
grep -Fq 'g_variant_lookup(props, "Name", "&s", &name);' "$btctl_source"
grep -Fq 'g_variant_lookup(props, "Powered", "b", &powered);' "$btctl_source"
grep -Fq 'g_variant_lookup(props, "Discoverable", "b", &discoverable);' "$btctl_source"
grep -Fq 'g_variant_lookup(props, "Pairable", "b", &pairable);' "$btctl_source"
grep -Fq 'g_variant_lookup(props, "Discovering", "b", &discovering);' "$btctl_source"
grep -Fq 'g_print("%s|%s|%s|%s|%d|%d|%d|%d\n"' "$btctl_source"
grep -Fq 'mkdir -p /tmp/lib/bluetooth' "$wrapper"
if grep -Rqs '/var/lib/bluetooth' "$wrapper" "$btctl_source"; then
    echo 'ERROR: Bluetooth runtime state must not depend on /var persistence semantics.' >&2
    exit 1
fi

echo 'Minimal Bluetooth audio dependency tests passed.'
