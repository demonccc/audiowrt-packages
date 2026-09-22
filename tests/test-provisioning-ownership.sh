#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ctl=audiowrt-provisioning/files/audiowrtctl
worker=audiowrt-provisioning/files/audiowrt-provision
runtime=audiowrt-wifi-client/files/audiowrt-wifi-runtime
ap=audiowrt-provisioning/files/setup-ap
grep -q 'audiowrt_connected' "$ctl"
! grep -q 'has_persistent_wifi_client' "$ctl"
grep -q 'scope global' "$runtime"
grep -q 'type managed' "$runtime"
grep -q 'carrier' "$runtime"
grep -q 'wifi.verified' "$worker"
! grep -q 'commit-client' "$worker"
grep -q 'commit-client' audiowrt-provisioning/files/audiowrt-provision.cgi
grep -q 'action.*save' audiowrt-provisioning/files/audiowrt-provision.cgi
grep -q 'provision-supervisor' audiowrt-provisioning/files/audiowrt-provisioning.init
grep -q 'provisioning.saved' audiowrt-provisioning/files/provision-supervisor
grep -q 'hostapd.*hostapd.conf' "$ap"
grep -q 'udhcpd -f' "$ap"
! test -f audiowrt-udhcpd/files/udhcpd.init
! grep -q 'uci.*commit' "$ctl" "$worker" "$ap"
printf 'Provisioning ownership checks passed.\n'
