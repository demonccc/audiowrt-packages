#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

printf 'Content-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
[ "${REQUEST_METHOD:-GET}" = 'GET' ] || exit 0
[ "$(/usr/sbin/audiowrtctl status 2>/dev/null | sed -n 's/^provisioning=//p')" = '1' ] || exit 0
exec /usr/sbin/audiowrt-wifi-client radios
