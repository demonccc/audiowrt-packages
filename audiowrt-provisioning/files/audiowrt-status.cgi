#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

json_escape() { printf '%s' "$1" | tr '\r\n' '  ' | sed 's/\\/\\\\/g; s/"/\\"/g'; }
name="$(uci -q get system.@system[0].hostname || echo AudioWRT)"
provisioning="$(uci -q get audiowrt.main.provisioning || echo 1)"
wifi_ssid="$(uci -q get wireless.audiowrt_client.ssid || true)"
last_error="$(uci -q get audiowrt.main.last_error || true)"
audio_ready="$(uci -q get audiowrt-audio.main.ready || echo 0)"
audio_device="$(uci -q get audiowrt-audio.main.device || true)"
output_type="$(uci -q get audiowrt-audio.main.output_type || echo auto)"
network_status="$(ubus call network.interface.audiowrt_wifi status 2>/dev/null || true)"
ip_address="$(printf '%s\n' "$network_status" | sed -n '/"ipv4-address"/,/]/ s/.*"address":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
printf '{"device_name":"%s","provisioning":%s,"audio_ready":%s,"audio_device":"%s","output_type":"%s","wifi_ssid":"%s","ip_address":"%s","last_error":"%s"}\n' \
	"$(json_escape "$name")" "$([ "$provisioning" = '1' ] && echo true || echo false)" "$([ "$audio_ready" = '1' ] && echo true || echo false)" \
	"$(json_escape "$audio_device")" "$(json_escape "$output_type")" "$(json_escape "$wifi_ssid")" "$(json_escape "$ip_address")" "$(json_escape "$last_error")"
