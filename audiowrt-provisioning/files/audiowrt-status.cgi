#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
. /usr/libexec/audiowrt/wifi-runtime

json_escape() { printf '%s' "$1" | tr '\r\n' '  ' | sed 's/\\/\\\\/g; s/"/\\"/g'; }
name="$(uci -q get system.@system[0].hostname || echo AudioWRT)"
wifi_ssid="$(uci -q get wireless.audiowrt_client.ssid || true)"
last_error="$(cat /tmp/audiowrt/provisioning.error 2>/dev/null || true)"
setup_ip="$AUDIOWRT_SETUP_IP"
done_file=/tmp/audiowrt/provisioning.done

audio_status="$(/usr/sbin/audiowrt-audio status 2>/dev/null || true)"
audio_ready="$(printf '%s\n' "$audio_status" | sed -n 's/^ready=//p' | head -n 1)"
audio_device="$(printf '%s\n' "$audio_status" | sed -n 's/^device=//p' | head -n 1)"
output_type="$(printf '%s\n' "$audio_status" | sed -n 's/^output_type=//p' | head -n 1)"
[ -n "$audio_ready" ] || audio_ready=0
[ -n "$output_type" ] || output_type=auto

wifi_status="$(ubus call network.interface.audiowrt_wifi status 2>/dev/null || true)"
provisioning=0
if [ ! -f "$done_file" ] && { audiowrt_setup_active || [ -d /tmp/audiowrt/provision-request ]; }; then
	provisioning=1
fi
verified=false
[ ! -f /tmp/audiowrt/wifi.verified ] || verified=true

ip_address="$(printf '%s\n' "$wifi_status" | sed -n '/"ipv4-address"/,/]/ s/.*"address":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
if [ -z "$ip_address" ]; then
	lan_status="$(ubus call network.interface.lan status 2>/dev/null || true)"
	ip_address="$(printf '%s\n' "$lan_status" | sed -n '/"ipv4-address"/,/]/ s/.*"address":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
fi

printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
printf '{"device_name":"%s","verified":%s,"provisioning":%s,"audio_ready":%s,"audio_device":"%s","output_type":"%s","wifi_ssid":"%s","ip_address":"%s","last_error":"%s"}\n' \
	"$(json_escape "$name")" "$verified" "$([ "$provisioning" -eq 1 ] && echo true || echo false)" "$([ "$audio_ready" = '1' ] && echo true || echo false)" \
	"$(json_escape "$audio_device")" "$(json_escape "$output_type")" "$(json_escape "$wifi_ssid")" "$(json_escape "$ip_address")" "$(json_escape "$last_error")"
