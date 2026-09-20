#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
alsa="$repo_root/libaudiowrt-alsa-minimal/Makefile"
bluetooth="$repo_root/audiowrt-kmod-bluetooth/Makefile"
bluetooth_integration="$repo_root/audiowrt-bluetooth/Makefile"

# ALSA keeps the PCM paths and built-in hw control used by AudioWRT USB Audio
# and BlueALSA, but drops external control, MIDI and general-purpose plugins.
for keep in '--with-pcm-plugins=linear,route,rate,plug,dmix,ioplug' '--with-ctl-plugins='; do
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
grep -q '^define Package/libaudiowrt-alsa-minimal$' "$alsa"
grep -q '^  PROVIDES:=alsa-lib$' "$alsa"
! grep -q '^  CONFLICTS:=' "$alsa"

# ALSA is a userspace library. Kernel sound modules belong to the concrete
# USB-audio flavor, not to the library package. Any kmod dependency here makes
# a Bluetooth source build recurse into package/kernel/linux.
if grep -Eq 'kmod-sound-core' "$alsa"; then
	echo 'ERROR: minimal ALSA must not force kmod-sound-core.' >&2
	exit 1
fi

# TLS stays entirely on OpenWrt's official libmbedtls runtime. AudioWRT must not
# reintroduce a custom replacement package here.
test ! -e "$repo_root/audiowrt-minimal-mbedtls/Makefile"

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
echo 'Minimal runtime-library contracts passed.'
