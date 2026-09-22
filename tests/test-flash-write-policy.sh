#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
! grep -R -n -E --include=Makefile 'uci-defaults' .
! test -d audiowrt-storage
! test -d luci-app-audiowrt-storage
! test -f audiowrt-audio/files/audiowrt-audio.init
! grep -R -n -E 'uci .*commit|>[[:space:]]*/etc/' audiowrt-usb-audio/files audiowrt-audio/files audiowrt-provisioning/files/audiowrt-provisioning.init audiowrt-dlna/files/audiowrt-dlna.init
! grep -n -E 'killall|uci .* (set|delete|commit)' audiowrt-provisioning/files/setup-ap
! grep -n -E 'sleep|setup-stop|commit' audiowrt-provisioning/files/audiowrt-status.cgi
! grep -R -n -E 'uci .*commit' audiowrt-wifi-client/files audiowrt-bluetooth/files audiowrt-extensions/files
grep -qF '/tmp/audiowrt-dlna' audiowrt-dlna/src/renderer-part-00.inc
grep -qF -- '--localstatedir=/tmp' audiowrt-bluez/Makefile
grep -qF 'BLUEZ_STORAGE "/tmp/lib/bluetooth"' audiowrt-btctl/src/audiowrt-btctl.c
grep -qF 'SAVE_PREFIX=' audiowrt-config/files/config-save
grep -qF 'cmp -s' audiowrt-config/files/config-save
grep -qF 'save_finish' audiowrt-bluetooth/files/audiowrt-bluetooth
printf 'Flash write ownership checks passed.\n'
