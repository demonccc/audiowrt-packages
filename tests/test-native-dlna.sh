#!/usr/bin/env bash
set -euo pipefail

fail() { echo "native renderer contract failed: $*" >&2; exit 1; }

[[ -f audiowrt-dlna/src/audiowrt-dlna.c ]] || fail "renderer source missing"
[[ -f audiowrt-player-core/src/audiowrt-player.c ]] || fail "player core source missing"

grep -q '^PKG_NAME:=audiowrt-renderer$' audiowrt-dlna/Makefile || fail "renderer package name mismatch"
grep -q 'PROVIDES:=audiowrt-dlna' audiowrt-dlna/Makefile || fail "renderer compatibility provide missing"

renderer_sources=$(cat audiowrt-dlna/src/*)
for token in \
  'MediaRenderer:1' \
  'AVTransport:1' \
  'RenderingControl:1' \
  'ConnectionManager:1' \
  'SetAVTransportURI' \
  'SUBSCRIBE' \
  'M-SEARCH' \
  '224.0.0.251' \
  '_http._tcp.local' \
  '_services._dns-sd._udp.local' \
  'open_mdns' \
  'handle_mdns'; do
  grep -q "$token" <<<"$renderer_sources" || fail "renderer is missing $token"
done

[[ ! -e audiowrt-mdns/Makefile ]] || fail "standalone mDNS package must not exist"
grep -q '/usr/libexec/audiowrt-renderer' audiowrt-dlna/files/audiowrt-dlna.init || fail "procd must launch unified renderer"

grep -q '+libuclient' audiowrt-player-core/Makefile || fail "player core must depend on libuclient"
grep -q '+alsa-lib' audiowrt-player-core/Makefile || fail "player core must depend on ALSA"
grep -q 'uclient_new' audiowrt-player-core/src/audiowrt-player.c || fail "player core must use libuclient directly"

if grep -REn 'execl.*(wget|uclient-fetch|curl)|system.*(wget|uclient-fetch|curl)' \
  audiowrt-player-core/src audiowrt-player-flac/src audiowrt-player-mp3/src \
  audiowrt-player-aac/src audiowrt-player-wav/src; then
  fail "official players must not spawn an external HTTP client"
fi

check_player() {
  local codec="$1" lib="$2" binary="audiowrt-player-$1"
  [[ -f "$binary/Makefile" ]] || fail "$binary Makefile missing"
  [[ -f "$binary/src/$binary.c" ]] || fail "$binary source missing"
  [[ -f "$binary/files/$codec.conf" ]] || fail "$codec descriptor missing"
  grep -q "+audiowrt-player-core" "$binary/Makefile" || fail "$binary must use player core"
  [[ -z "$lib" ]] || grep -q "$lib" "$binary/Makefile" || fail "$binary must depend/link on $lib"
  grep -q "command=/usr/bin/$binary" "$binary/files/$codec.conf" || fail "$codec descriptor command mismatch"
}

check_player flac libflac
check_player mp3 libmpg123
check_player aac libfaad2
check_player wav ''

grep -q '^PKG_NAME:=luci-app-audiowrt-renderer$' luci-app-audiowrt-dlna/Makefile || fail "LuCI package name mismatch"
[[ -f luci-app-audiowrt-dlna/root/usr/share/luci/menu.d/luci-app-audiowrt-dlna.json ]] || fail "LuCI menu missing"
[[ -f luci-app-audiowrt-dlna/root/usr/share/rpcd/acl.d/luci-app-audiowrt-dlna.json ]] || fail "LuCI ACL missing"
grep -q 'auto_command' luci-app-audiowrt-dlna/htdocs/luci-static/resources/view/audiowrt/dlna.js || fail "LuCI must expose overridden automatic player"
grep -q '/usr/libexec/audiowrt-renderer' luci-app-audiowrt-dlna/htdocs/luci-static/resources/view/audiowrt/dlna.js || fail "LuCI must query unified renderer"

sh -n audiowrt-dlna/files/audiowrt-dlna.init

echo "native renderer/discovery/player contract OK"
