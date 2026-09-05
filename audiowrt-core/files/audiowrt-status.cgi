#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

name="$(uci -q get audiowrt.main.device_name || echo AudioWRT)"
provisioning="$(uci -q get audiowrt.main.provisioning || echo 1)"
audio_ready="$(uci -q get audiowrt.main.audio_ready || echo 0)"
audio_device="$(uci -q get audiowrt.main.audio_device || true)"
wifi_ssid="$(uci -q get audiowrt.main.wifi_ssid || true)"
last_error="$(uci -q get audiowrt.main.last_error || true)"

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-store\r\n\r\n'
printf '{"device_name":"%s","provisioning":%s,"audio_ready":%s,"audio_device":"%s","wifi_ssid":"%s","last_error":"%s"}\n' \
	"$(json_escape "$name")" \
	"$([ "$provisioning" = "1" ] && echo true || echo false)" \
	"$([ "$audio_ready" = "1" ] && echo true || echo false)" \
	"$(json_escape "$audio_device")" \
	"$(json_escape "$wifi_ssid")" \
	"$(json_escape "$last_error")"
