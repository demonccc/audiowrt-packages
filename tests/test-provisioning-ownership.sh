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
grep -q 'channel=1' "$ap"
grep -q 'ip addr add.*AUDIOWRT_SETUP_IP/24' "$ap"
grep -q 'audiowrt_setup_dhcp_pool' "$ap"
grep -q 'udhcpd -f' "$ap"
grep -q 'provision-web start' "$ap"
grep -q 'provision-web stop' "$ap"
grep -q 'provisioning.error_page=/cgi-bin/provision-redirect' audiowrt-provisioning/files/provision-web
grep -q 'uhttpd.provisioning.home=.*WEB_DIR' audiowrt-provisioning/files/provision-web
grep -q 'uhttpd.provisioning.listen_http=.*AUDIOWRT_SETUP_IP' audiowrt-provisioning/files/provision-web
(
	. "$runtime"
	AUDIOWRT_SETUP_IP=10.42.17.1
	[ "$(audiowrt_setup_dhcp_pool)" = '10.42.17.100 10.42.17.199' ]
	AUDIOWRT_SETUP_IP=192.168.77.150
	[ "$(audiowrt_setup_dhcp_pool)" = '192.168.77.1 192.168.77.99' ]
)
! test -f audiowrt-udhcpd/files/udhcpd.init
! grep -q 'uci.*commit' "$ctl" "$worker" "$ap"
printf 'Provisioning ownership checks passed.\n'
