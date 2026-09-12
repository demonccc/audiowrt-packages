#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

json_escape() { printf '%s' "$1" | tr '\r\n' '  ' | sed 's/\\/\\\\/g; s/"/\\"/g'; }
reply() {
	code="$1"; message="$2"
	printf 'Status: %s\r\nContent-Type: application/json\r\nCache-Control: no-store\r\n\r\n' "$code"
	printf '{"message":"%s"}\n' "$(json_escape "$message")"
	exit 0
}

[ "${REQUEST_METHOD:-}" = 'POST' ] || reply '405 Method Not Allowed' 'POST is required.'
[ "$(uci -q get audiowrt.main.provisioning || echo 0)" = '1' ] || reply '409 Conflict' 'AudioWRT is already provisioned.'
length="${CONTENT_LENGTH:-0}"
case "$length" in ''|*[!0-9]*) reply '400 Bad Request' 'Invalid request length.' ;; esac
[ "$length" -le 8192 ] || reply '413 Payload Too Large' 'Request is too large.'
body="$(dd bs=1 count="$length" 2>/dev/null)"

hostname_value=''; radio=''; ssid=''; bssid=''; encryption='sae-mixed'; wifi_key=''; admin_password=''; admin_confirm=''
old_ifs="$IFS"; IFS='&'
for pair in $body; do
	field="${pair%%=*}"
	value="${pair#*=}"
	decoded="$(uhttpd -d "$value" 2>/dev/null || true)"
	case "$field" in
		hostname) hostname_value="$decoded" ;;
		radio) radio="$decoded" ;;
		ssid) ssid="$decoded" ;;
		bssid) bssid="$decoded" ;;
		encryption) encryption="$decoded" ;;
		wifi_key) wifi_key="$decoded" ;;
		admin_password) admin_password="$decoded" ;;
		admin_confirm) admin_confirm="$decoded" ;;
	esac
done
IFS="$old_ifs"

[ -n "$hostname_value" ] || reply '400 Bad Request' 'Device name is required.'
printf '%s\n' "$hostname_value" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$' || reply '400 Bad Request' 'Device name may contain letters, numbers and hyphens only.'
[ -n "$radio" ] && uci -q get wireless."$radio" >/dev/null 2>&1 || reply '400 Bad Request' 'A valid Wi-Fi radio is required.'
[ -n "$ssid" ] || reply '400 Bad Request' 'SSID is required.'
[ "${#ssid}" -le 32 ] || reply '400 Bad Request' 'SSID must not exceed 32 characters.'
[ "$(printf '%s' "$ssid" | tr -d '\r\n')" = "$ssid" ] || reply '400 Bad Request' 'SSID must not contain line breaks.'
if [ -n "$bssid" ]; then
	printf '%s\n' "$bssid" | grep -Eq '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' || reply '400 Bad Request' 'Invalid BSSID.'
fi
case "$encryption" in none) wifi_key='' ;; psk2|sae|sae-mixed) ;; *) reply '400 Bad Request' 'Unsupported Wi-Fi security mode.' ;; esac
if [ "$encryption" != 'none' ]; then
	[ "${#wifi_key}" -ge 8 ] && [ "${#wifi_key}" -le 63 ] || reply '400 Bad Request' 'Wi-Fi password must contain between 8 and 63 characters.'
	[ "$(printf '%s' "$wifi_key" | tr -d '\r\n')" = "$wifi_key" ] || reply '400 Bad Request' 'Wi-Fi password must not contain line breaks.'
fi
[ "${#admin_password}" -ge 8 ] || reply '400 Bad Request' 'Admin password must contain at least 8 characters.'
[ "$(printf '%s' "$admin_password" | tr -d '\r\n')" = "$admin_password" ] || reply '400 Bad Request' 'Admin password must not contain line breaks.'
[ "$admin_password" = "$admin_confirm" ] || reply '400 Bad Request' 'Admin passwords do not match.'

uci -q set system.@system[0].hostname="$hostname_value" || reply '500 Internal Server Error' 'Could not update the device name.'
uci -q commit system || reply '500 Internal Server Error' 'Could not save the device name.'
hostname "$hostname_value" 2>/dev/null || true

if ! { printf '%s\n' "$admin_password"; sleep 1; printf '%s\n' "$admin_password"; } | /bin/busybox passwd root >/dev/null 2>&1; then
	reply '500 Internal Server Error' 'Could not set the administrator password.'
fi

uci -q set audiowrt.main.last_error=''
uci -q commit audiowrt
/usr/sbin/audiowrt-wifi-client mdns-sync >/dev/null 2>&1 || true

umask 077
request_dir="/tmp/audiowrt-provision.$$"
mkdir -p "$request_dir" || reply '500 Internal Server Error' 'Could not stage provisioning data.'
printf '%s' "$radio" > "$request_dir/radio"
printf '%s' "$ssid" > "$request_dir/ssid"
printf '%s' "$bssid" > "$request_dir/bssid"
printf '%s' "$encryption" > "$request_dir/encryption"
printf '%s' "$wifi_key" > "$request_dir/wifi_key"
/usr/libexec/audiowrt/provision-wifi "$request_dir" >/tmp/audiowrt-provision.log 2>&1 &
reply '202 Accepted' 'Configuration accepted. AudioWRT is connecting to the selected network.'
