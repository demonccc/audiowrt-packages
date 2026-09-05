#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

reply() {
	code="$1"
	message="$2"
	printf 'Status: %s\r\n' "$code"
	printf 'Content-Type: application/json\r\n'
	printf 'Cache-Control: no-store\r\n\r\n'
	printf '{"message":"%s"}\n' "$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')"
	exit 0
}

[ "${REQUEST_METHOD:-}" = "POST" ] || reply "405 Method Not Allowed" "POST is required."
[ "$(uci -q get audiowrt.main.provisioning || echo 0)" = "1" ] || reply "409 Conflict" "AudioWRT is already provisioned."

length="${CONTENT_LENGTH:-0}"
case "$length" in
	''|*[!0-9]*) reply "400 Bad Request" "Invalid request length." ;;
esac
[ "$length" -le 4096 ] || reply "413 Payload Too Large" "Request is too large."

body="$(dd bs=1 count="$length" 2>/dev/null)"
ssid=""
key=""
encryption="sae-mixed"

old_ifs="$IFS"
IFS='&'
for pair in $body; do
	field="${pair%%=*}"
	value="${pair#*=}"
	decoded="$(uhttpd -d "$value" 2>/dev/null || true)"
	case "$field" in
		ssid) ssid="$decoded" ;;
		key) key="$decoded" ;;
		encryption) encryption="$decoded" ;;
	esac
done
IFS="$old_ifs"

[ -n "$ssid" ] || reply "400 Bad Request" "SSID is required."

case "$encryption" in
	none|psk2|sae|sae-mixed) ;;
	*) reply "400 Bad Request" "Unsupported Wi-Fi security mode." ;;
esac

if [ "$encryption" != "none" ] && [ "${#key}" -lt 8 ]; then
	reply "400 Bad Request" "Wi-Fi password must contain at least 8 characters."
fi

/usr/libexec/audiowrt/provision-wifi "$ssid" "$encryption" "$key" >/tmp/audiowrt-provision.log 2>&1 &
reply "202 Accepted" "Configuration accepted. AudioWRT is connecting to the selected network."
