#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
! grep -R -n -E --include=Makefile 'uci-defaults' .
! test -d audiowrt/audiowrt-storage
! test -d audiowrt/luci-app-audiowrt-storage
! test -f audiowrt/audiowrt-audio/files/audiowrt-audio.init
! grep -R -n -E 'uci .*commit|>[[:space:]]*/etc/' audiowrt/audiowrt-usb-audio/files audiowrt/audiowrt-audio/files audiowrt/audiowrt-provisioning/files/audiowrt-provisioning.init audiowrt/audiowrt-dlna-renderer/files/audiowrt-dlna.init
! grep -n -E 'killall|uci .* (set|delete|commit)' audiowrt/audiowrt-provisioning/files/setup-ap
! grep -n -E 'sleep|setup-stop|commit' audiowrt/audiowrt-provisioning/files/audiowrt-status.cgi
! grep -R -n -E 'uci .*commit' audiowrt/audiowrt-wifi-client/files audiowrt/audiowrt-bluetooth/files
grep -qF '/tmp/audiowrt-dlna' audiowrt/audiowrt-dlna-renderer/src/renderer-part-00.inc
grep -qF -- '--localstatedir=/tmp' trimmed/bluez-trimmed/Makefile
grep -qF 'BLUEZ_STORAGE "/tmp/lib/bluetooth"' audiowrt/audiowrt-btctl/src/audiowrt-btctl.c
grep -qF 'SAVE_PREFIX=' audiowrt/audiowrt-config/files/config-save
grep -qF 'cmp -s' audiowrt/audiowrt-config/files/config-save
grep -qF 'save_finish' audiowrt/audiowrt-bluetooth/files/audiowrt-bluetooth
printf 'Flash write ownership checks passed.\n'
