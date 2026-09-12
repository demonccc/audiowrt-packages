#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
[ "${REQUEST_METHOD:-GET}" = 'GET' ] || exit 0
[ "$(uci -q get audiowrt.main.provisioning || echo 0)" = '1' ] || exit 0
[ -x /usr/sbin/audiowrt-wifi-client ] || exit 0
/usr/sbin/audiowrt-wifi-client scan | sed 's/^@@RADIO:\([^|]*\)|.*$/@@RADIO:\1/'
