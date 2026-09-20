#!/usr/bin/env bash
set -euo pipefail

fail() { echo "native renderer contract failed: $*" >&2; exit 1; }

[[ -f audiowrt-dlna/src/audiowrt-dlna.c ]] || fail "renderer source missing"
[[ -f libaudiowrt-player/src/audiowrt-player.c ]] || fail "player core source missing"
grep -q '^PKG_NAME:=libaudiowrt-player
grep -q '^PKG_NAME:=audiowrt-renderer$' audiowrt-dlna/Makefile || fail "renderer package name mismatch"
grep -q 'PROVIDES:=audiowrt-dlna' audiowrt-dlna/Makefile || fail "renderer compatibility provide missing"

if grep -Eq '(^|[+[:space:]])libuci([[:space:]]|$)|-luci' audiowrt-dlna/Makefile; then
  fail "renderer must not depend on libuci"
fi
if grep -Rqs '#include <uci.h>' audiowrt-dlna/src; then
  fail "renderer must not require uci.h"
fi
grep -q 'config_next_token' audiowrt-dlna/src/renderer-part-01.inc || fail "minimal renderer config parser missing"

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

grep -q '+libuclient' libaudiowrt-player/Makefile || fail "player core must depend on libuclient"
grep -q '+alsa-lib' libaudiowrt-player/Makefile || fail "player core must depend on ALSA"
grep -q 'uclient_new' libaudiowrt-player/src/audiowrt-player.c || fail "player core must use libuclient directly"

if grep -REn 'execl.*(wget|uclient-fetch|curl)|system.*(wget|uclient-fetch|curl)' \
  libaudiowrt-player/src audiowrt-player-flac/src audiowrt-player-mp3/src \
  audiowrt-player-aac/src audiowrt-player-wav/src; then
  fail "official players must not spawn an external HTTP client"
fi

check_player() {
  local codec="$1" lib="$2" binary="audiowrt-player-$1"
  [[ -f "$binary/Makefile" ]] || fail "$binary Makefile missing"
  [[ -f "$binary/src/$binary.c" ]] || fail "$binary source missing"
  [[ -f "$binary/files/$codec.conf" ]] || fail "$codec descriptor missing"
  grep -q "+libaudiowrt-player" "$binary/Makefile" || fail "$binary must use player core"
  [[ -z "$lib" ]] || grep -q "$lib" "$binary/Makefile" || fail "$binary must depend/link on $lib"
  grep -q "command=/usr/bin/$binary" "$binary/files/$codec.conf" || fail "$codec descriptor command mismatch"
}

check_player flac libflac
flac_source="audiowrt-player-flac/src/audiowrt-player-flac.c"
grep -q 'SND_PCM_FORMAT_S16 : SND_PCM_FORMAT_S32' "$flac_source" || fail "FLAC player must use native-endian ALSA PCM formats"
if grep -Eq 'SND_PCM_FORMAT_(S16|S32)_(LE|BE)' "$flac_source"; then
  fail "FLAC player must not hard-code PCM byte order"
fi
if awk '/FLAC__stream_decoder_finish\(decoder\)/ { finished=1 } finished && /fclose\(input\)/ { bad=1 } END { exit bad ? 0 : 1 }' "$flac_source"; then
  fail "FLAC player must not fclose the FILE after libFLAC finish takes ownership"
fi
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
 libaudiowrt-player/Makefile || fail "player library package name mismatch"
[[ ! -e audiowrt-player-core/Makefile ]] || fail "legacy player-core package must not exist"

grep -q '^PKG_NAME:=audiowrt-renderer$' audiowrt-dlna/Makefile || fail "renderer package name mismatch"
grep -q 'PROVIDES:=audiowrt-dlna' audiowrt-dlna/Makefile || fail "renderer compatibility provide missing"

if grep -Eq '(^|[+[:space:]])libuci([[:space:]]|$)|-luci' audiowrt-dlna/Makefile; then
  fail "renderer must not depend on libuci"
fi
if grep -Rqs '#include <uci.h>' audiowrt-dlna/src; then
  fail "renderer must not require uci.h"
fi
grep -q 'config_next_token' audiowrt-dlna/src/renderer-part-01.inc || fail "minimal renderer config parser missing"

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

grep -q '+libuclient' libaudiowrt-player/Makefile || fail "player core must depend on libuclient"
grep -q '+alsa-lib' libaudiowrt-player/Makefile || fail "player core must depend on ALSA"
grep -q 'uclient_new' libaudiowrt-player/src/audiowrt-player.c || fail "player core must use libuclient directly"

if grep -REn 'execl.*(wget|uclient-fetch|curl)|system.*(wget|uclient-fetch|curl)' \
  libaudiowrt-player/src audiowrt-player-flac/src audiowrt-player-mp3/src \
  audiowrt-player-aac/src audiowrt-player-wav/src; then
  fail "official players must not spawn an external HTTP client"
fi

check_player() {
  local codec="$1" lib="$2" binary="audiowrt-player-$1"
  [[ -f "$binary/Makefile" ]] || fail "$binary Makefile missing"
  [[ -f "$binary/src/$binary.c" ]] || fail "$binary source missing"
  [[ -f "$binary/files/$codec.conf" ]] || fail "$codec descriptor missing"
  grep -q "+libaudiowrt-player" "$binary/Makefile" || fail "$binary must use player core"
  [[ -z "$lib" ]] || grep -q "$lib" "$binary/Makefile" || fail "$binary must depend/link on $lib"
  grep -q "command=/usr/bin/$binary" "$binary/files/$codec.conf" || fail "$codec descriptor command mismatch"
}

check_player flac libflac
flac_source="audiowrt-player-flac/src/audiowrt-player-flac.c"
grep -q 'SND_PCM_FORMAT_S16 : SND_PCM_FORMAT_S32' "$flac_source" || fail "FLAC player must use native-endian ALSA PCM formats"
if grep -Eq 'SND_PCM_FORMAT_(S16|S32)_(LE|BE)' "$flac_source"; then
  fail "FLAC player must not hard-code PCM byte order"
fi
if awk '/FLAC__stream_decoder_finish\(decoder\)/ { finished=1 } finished && /fclose\(input\)/ { bad=1 } END { exit bad ? 0 : 1 }' "$flac_source"; then
  fail "FLAC player must not fclose the FILE after libFLAC finish takes ownership"
fi
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
