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

setup_status="$(ubus call network.interface.audiowrt_setup status 2>/dev/null || true)"
wifi_status="$(ubus call network.interface.audiowrt_wifi status 2>/dev/null || true)"
setup_active=0
wifi_up=0
if printf '%s\n' "$setup_status" | grep -q '"up":[[:space:]]*true' &&
   printf '%s\n' "$setup_status" | grep -q "\"address\":[[:space:]]*\"$setup_ip\""; then
	setup_active=1
fi
printf '%s\n' "$wifi_status" | grep -q '"up":[[:space:]]*true' && wifi_up=1

# Provisioning is a fact derived from live networking, not a stored boolean.
# Report Done only after the verified Wi-Fi client has been committed. Merely
# seeing the interface come up is not enough: the worker may still be saving
# the configuration. The completion marker lives only in tmpfs.
provisioning=0
if [ "$setup_active" -eq 1 ] && [ ! -f "$done_file" ]; then
	provisioning=1
fi

ip_address="$(printf '%s\n' "$wifi_status" | sed -n '/"ipv4-address"/,/]/ s/.*"address":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
if [ -z "$ip_address" ]; then
	lan_status="$(ubus call network.interface.lan status 2>/dev/null || true)"
	ip_address="$(printf '%s\n' "$lan_status" | sed -n '/"ipv4-address"/,/]/ s/.*"address":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
fi

printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
printf '{"device_name":"%s","provisioning":%s,"audio_ready":%s,"audio_device":"%s","output_type":"%s","wifi_ssid":"%s","ip_address":"%s","last_error":"%s"}\n' \
	"$(json_escape "$name")" "$([ "$provisioning" -eq 1 ] && echo true || echo false)" "$([ "$audio_ready" = '1' ] && echo true || echo false)" \
	"$(json_escape "$audio_device")" "$(json_escape "$output_type")" "$(json_escape "$wifi_ssid")" "$(json_escape "$ip_address")" "$(json_escape "$last_error")"

if [ "$setup_active" -eq 1 ] && [ "$wifi_up" -eq 1 ] && [ -f "$done_file" ]; then
	(
		sleep 5
		/usr/sbin/audiowrt-wifi-client setup-stop >/dev/null 2>&1 || true
	) </dev/null >/dev/null 2>&1 &
fi
