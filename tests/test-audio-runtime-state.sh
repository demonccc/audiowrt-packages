#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

audio="$repo_root/audiowrt-audio/files/audiowrt-audio"
audio_makefile="$repo_root/audiowrt-audio/Makefile"
audio_init="$repo_root/audiowrt-audio/files/audiowrt-audio.init"
usb="$repo_root/audiowrt-usb-audio/files/select-audio-output"
bluetooth="$repo_root/audiowrt-bluetooth/files/audiowrt-bluetooth"
bluetooth_makefile="$repo_root/audiowrt-bluetooth/Makefile"
bluetooth_config="$repo_root/audiowrt-bluetooth/files/audiowrt-bluetooth.config"
bluetooth_init="$repo_root/audiowrt-bluetooth/files/audiowrt-bluetooth.init"
btctl="$repo_root/audiowrt-btctl/src/audiowrt-btctl.c"
luci="$repo_root/luci-app-audiowrt/htdocs/luci-static/resources/view/audiowrt/output.js"

# Both output implementations use the same volatile state writer.
shared="$repo_root/audiowrt-audio/files/audio-runtime"
for script in "$audio" "$usb" "$bluetooth"; do
    grep -q '/usr/libexec/audiowrt/audio-runtime' "$script"
done
grep -q 'RUNTIME_DIR=/tmp/audiowrt' "$shared"
grep -q 'cmp -s' "$shared"
grep -q 'enabled &&' "$shared"
[ ! -e "$audio_init" ]
! grep -q 'asound.conf.*: >' "$audio_makefile"
awk '/^devices\(\)/,/^}/' "$bluetooth" | (! grep -q ensure_services)
grep -q '^config bluetooth .main' "$bluetooth_config"
grep -q "option preferred_device ''" "$bluetooth_config"
grep -q '/etc/config/audiowrt-bluetooth' "$bluetooth_makefile"
grep -q 'storage-export' "$bluetooth"
grep -q 'storage-import' "$bluetooth"
grep -q 'g_base64_encode' "$btctl"
grep -q 'g_base64_decode' "$btctl"
grep -q '#define BLUEZ_STORAGE "/tmp/lib/bluetooth"' "$btctl"
if grep -q '/var/lib/bluetooth' "$btctl" "$bluetooth"; then
	echo 'ERROR: Bluetooth runtime pairing database must remain in tmpfs.' >&2
	exit 1
fi

# Saved state is restored before bluetoothd (START=60) and reconnect runs from RAM.
grep -q '^START=59$' "$bluetooth_init"
grep -q 'audiowrt-bluetooth restore' "$bluetooth_init"
grep -q 'audiowrt-bluetooth watch' "$bluetooth_init"
grep -q 'bluetooth.blocked' "$bluetooth"
grep -q 'watch_saved' "$bluetooth"

# A persisted preferred device must recreate the volatile ALSA route and
# selected runtime state during boot, before any successful reconnect.
grep -q '^prime_saved_output()' "$bluetooth"
grep -q 'prime_saved_output' "$bluetooth"
grep -Fq 'write_asound_config "$mac"' "$bluetooth"
grep -Fq 'write_runtime_state "$mac" "$name" 0 "Waiting for saved Bluetooth output."' "$bluetooth"
grep -Fq '[ "$(runtime_ready)" != "1" ]' "$bluetooth"

# LuCI separates known devices from discovery and polls runtime state.
for token in 'My devices' 'Nearby devices' 'Scan for devices' "_('Pair')" "_('Connect')" "_('Use')" "_('Disconnect')" "_('Save')" 'poll.add'; do
	grep -Fq "$token" "$luci" || {
		echo "ERROR: Bluetooth LuCI flow is missing: $token" >&2
		exit 1
	}
done

printf 'Audio/Bluetooth tmpfs and explicit-save contract passed.\n'
