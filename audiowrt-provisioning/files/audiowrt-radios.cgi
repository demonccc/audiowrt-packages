#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

printf 'Content-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
[ "${REQUEST_METHOD:-GET}" = 'GET' ] || exit 0
[ "$(uci -q get audiowrt.main.provisioning || echo 0)" = '1' ] || exit 0
exec /usr/sbin/audiowrt-wifi-client radios
