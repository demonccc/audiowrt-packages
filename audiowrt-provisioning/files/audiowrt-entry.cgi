#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

. /usr/libexec/audiowrt/wifi-runtime

host=${HTTP_HOST%%:*}
case "$host" in
    "$AUDIOWRT_SETUP_IP") target=/audiowrt.html ;;
    *) target=/cgi-bin/luci/ ;;
esac

printf 'Status: 302 Found\r\n'
printf 'Location: %s\r\n' "$target"
printf 'Cache-Control: no-store\r\n'
printf 'Content-Type: text/plain\r\n'
printf '\r\n'
printf 'Redirecting to %s\n' "$target"
