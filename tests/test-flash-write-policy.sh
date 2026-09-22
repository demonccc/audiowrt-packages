#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
! rg 'uci-defaults' --glob Makefile
! test -d audiowrt-storage
! test -d luci-app-audiowrt-storage
! test -f audiowrt-audio/files/audiowrt-audio.init
! rg 'uci .*commit|>[[:space:]]*/etc/' audiowrt-usb-audio/files audiowrt-audio/files audiowrt-provisioning/files/audiowrt-provisioning.init audiowrt-dlna/files/audiowrt-dlna.init
! rg 'killall|uci .* (set|delete|commit)' audiowrt-provisioning/files/setup-ap
! rg 'sleep|setup-stop|commit' audiowrt-provisioning/files/audiowrt-status.cgi
! rg 'uci .*commit' audiowrt-wifi-client/files audiowrt-bluetooth/files audiowrt-extensions/files
rg -q '/tmp/audiowrt-dlna' audiowrt-dlna/src/renderer-part-00.inc
rg -q -- '--localstatedir=/tmp' audiowrt-bluez/Makefile
rg -q 'BLUEZ_STORAGE "/tmp/lib/bluetooth"' audiowrt-btctl/src/audiowrt-btctl.c
rg -q 'SAVE_PREFIX=' audiowrt-config/files/config-save
rg -q 'cmp -s' audiowrt-config/files/config-save
rg -q 'save_finish' audiowrt-bluetooth/files/audiowrt-bluetooth
printf 'Flash write ownership checks passed.\n'
