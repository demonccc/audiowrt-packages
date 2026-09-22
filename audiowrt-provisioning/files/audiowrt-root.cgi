#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
. /usr/libexec/audiowrt/wifi-runtime

redirect() {
	printf 'Status: 302 Found\r\n'
	printf 'Location: %s\r\n' "$1"
	printf 'Cache-Control: no-store\r\n'
	printf 'Content-Type: text/plain\r\n\r\n'
	printf 'Redirecting to %s\n' "$1"
	exit 0
}

setup_ip="$AUDIOWRT_SETUP_IP"
host="${HTTP_HOST:-}"
host="${host%%:*}"

# The destination address is the provisioning state. The same hostname may
# resolve to a normal LAN address or to the temporary setup address, so never
# use a separate persistent boolean to decide which UI to serve.
if [ "${SERVER_ADDR:-}" = "$setup_ip" ] || [ "$host" = "$setup_ip" ]; then
	redirect '/audiowrt.html'
fi

redirect '/cgi-bin/luci/'
