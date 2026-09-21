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

# Recurrent runtime state belongs to tmpfs, never UCI/overlay.
grep -q '/tmp/audiowrt/audio.state' "$audio"
grep -q '^START=10$' "$audio_init"
grep -Fq '[ -e /tmp/audiowrt/asound.conf ] || : > /tmp/audiowrt/asound.conf' "$audio_init"
grep -Fq '[ -e /tmp/audiowrt/asound.conf ] || : > /tmp/audiowrt/asound.conf' "$audio_makefile"
grep -Fq '/etc/init.d/audiowrt-audio enable' "$audio_makefile"
grep -Fq './files/audiowrt-audio.init' "$audio_makefile"
grep -q 'RUNTIME_DIR=/tmp/audiowrt' "$usb"
grep -q 'RUNTIME_DIR=/tmp/audiowrt' "$bluetooth"
grep -Fq 'ASOUND_FILE="$RUNTIME_DIR/asound.conf"' "$usb"
grep -Fq 'ASOUND_FILE="$RUNTIME_DIR/asound.conf"' "$bluetooth"

if grep -Eq 'uci .*commit|uci .*set .*ready|uci .*set .*last_error|/etc/asound\.conf' "$audio" "$usb"; then
	echo 'ERROR: recurrent audio runtime state still writes persistent flash.' >&2
	exit 1
fi

# Bluetooth may commit only inside the explicit save_device operation.
commit_count="$(grep -c 'uci -q commit' "$bluetooth" || true)"
[ "$commit_count" -eq 1 ] || {
	echo "ERROR: Bluetooth runtime has $commit_count persistent commits; expected only explicit Save." >&2
	exit 1
}
awk '
	/^save_device\(\)/ { in_save=1 }
	in_save && /uci -q commit/ { found=1 }
	/^restore_saved\(\)/ { in_save=0 }
	END { exit found ? 0 : 1 }
' "$bluetooth" || {
	echo 'ERROR: Bluetooth persistent commit is not scoped to save_device().' >&2
	exit 1
}

grep -q '^config bluetooth .main' "$bluetooth_config"
grep -q "option preferred_device ''" "$bluetooth_config"
grep -q '/etc/config/audiowrt-bluetooth' "$bluetooth_makefile"
grep -q 'storage-export' "$bluetooth"
grep -q 'storage-import' "$bluetooth"
grep -q 'g_base64_encode' "$btctl"
grep -q 'g_base64_decode' "$btctl"
grep -q '#define BLUEZ_STORAGE "/var/lib/bluetooth"' "$btctl"

# The base audio service creates an empty valid runtime ALSA config before
# Bluetooth/USB services can replace it, so /etc/asound.conf is never dangling.
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
