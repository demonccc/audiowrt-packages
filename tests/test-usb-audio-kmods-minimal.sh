#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sound="$repo_root/packages/audiowrt-kmod-sound-core/Makefile"
usb="$repo_root/packages/audiowrt-kmod-usb-audio/Makefile"

test -f "$sound"
test -f "$usb"

grep -q '^AUDIOWRT_SOUND_CORE_PROVIDES:=kmod-sound-core$' "$sound"
grep -q '^AUDIOWRT_USB_AUDIO_PROVIDES:=kmod-usb-audio$' "$usb"
grep -q '^ifneq ($(DUMP),1)$' "$sound"
grep -q '^ifneq ($(DUMP),1)$' "$usb"
! grep -q '^  CONFLICTS:=' "$sound"
! grep -q '^  CONFLICTS:=' "$usb"

for keep in soundcore.ko snd.ko snd-hwdep.ko snd-seq-device.ko snd-rawmidi.ko snd-timer.ko snd-pcm.ko; do
	grep -Fq "$keep" "$sound"
done
for drop in snd-mixer-oss.ko snd-pcm-oss.ko snd-compress.ko; do
	if grep -Fq "$drop" "$sound"; then
		echo "ERROR: minimal sound core includes $drop" >&2
		exit 1
	fi
done

for keep in snd-usbmidi-lib.ko snd-usb-audio.ko; do
	grep -Fq "$keep" "$usb"
done
grep -q 'DEPENDS:=.*+kmod-audiowrt-sound-core' "$usb"
grep -q '+kmod-media-controller +kmod-sound-midi2' "$usb"

printf 'Minimal USB Audio kernel package contracts passed.\n'
