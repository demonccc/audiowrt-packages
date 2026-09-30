#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
. /usr/libexec/audiowrt/wifi-runtime

printf 'Content-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
[ "${REQUEST_METHOD:-GET}" = 'GET' ] || exit 0
[ "$(/usr/sbin/audiowrtctl status 2>/dev/null | sed -n 's/^provisioning=//p')" = '1' ] || exit 0
setup_radio="$(cat "$AUDIOWRT_SETUP_DIR/radio" 2>/dev/null || true)"
/usr/sbin/audiowrt-wifi-client radios 2>/dev/null | while IFS='|' read -r radio band channel; do
	[ -n "$radio" ] || continue
	[ "$radio" != "$setup_radio" ] || continue
	printf '%s|%s|%s\n' "$radio" "$band" "$channel"
done
