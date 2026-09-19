#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

redirect() {
	printf 'Status: 302 Found\r\n'
	printf 'Location: %s\r\n' "$1"
	printf 'Cache-Control: no-store\r\n'
	printf 'Content-Type: text/plain\r\n\r\n'
	printf 'Redirecting to %s\n' "$1"
	exit 0
}

provisioning="$(uci -q get audiowrt.main.provisioning || echo 1)"
setup_ip="$(uci -q get audiowrt.main.setup_ip || echo 192.168.77.1)"
host="${HTTP_HOST:-}"
host="${host%%:*}"

if [ "$provisioning" = '1' ]; then
	case "$host" in
		audiowrt.local|audiowrt.local.)
			redirect "http://$setup_ip/"
			;;
	esac

	if [ "$host" = "$setup_ip" ] || [ "${SERVER_ADDR:-}" = "$setup_ip" ]; then
		redirect '/audiowrt.html'
	fi
fi

redirect '/cgi-bin/luci/'
