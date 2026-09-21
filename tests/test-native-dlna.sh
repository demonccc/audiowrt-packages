#!/usr/bin/env bash
set -euo pipefail

fail() { echo "native renderer contract failed: $*" >&2; exit 1; }

[[ -f audiowrt-dlna/src/audiowrt-dlna.c ]] || fail "renderer source missing"
[[ -f libaudiowrt-player/src/audiowrt-player.c ]] || fail "player library source missing"
[[ -f libaudiowrt-player/files/audiowrt-playback-registry ]] || fail "UCI playback registry helper missing"
[[ -f libaudiowrt-player/files/audiowrt-player-registry ]] || fail "compatibility player registry alias missing"
[[ -f libaudiowrt-player/files/audiowrt-codecs.config ]] || fail "codec catalog config missing"
[[ -f libaudiowrt-player/files/audiowrt-players.config ]] || fail "player catalog config missing"

grep -q '^PKG_NAME:=libaudiowrt-player$' libaudiowrt-player/Makefile || fail "player library package name mismatch"
grep -q 'audiowrt-playback-registry' libaudiowrt-player/Makefile || fail "player library must install playback registry helper"
grep -q '/etc/config/audiowrt-codecs' libaudiowrt-player/Makefile || fail "player library must install codec catalog"
grep -q '/etc/config/audiowrt-players' libaudiowrt-player/Makefile || fail "player library must install player catalog"
[[ ! -e audiowrt-player-core/Makefile ]] || fail "legacy player-core package must not exist"

grep -q '^PKG_NAME:=audiowrt-renderer$' audiowrt-dlna/Makefile || fail "renderer package name mismatch"
grep -q 'PROVIDES:=audiowrt-dlna' audiowrt-dlna/Makefile || fail "renderer compatibility provide missing"

if grep -Eq '(^|[+[:space:]])libuci([[:space:]]|$)|-luci' audiowrt-dlna/Makefile; then
  fail "renderer must not depend on libuci"
fi
if grep -Rqs '#include <uci.h>' audiowrt-dlna/src; then
  fail "renderer must not require uci.h"
fi

grep -q 'config_next_token' audiowrt-dlna/src/renderer-part-01.inc || fail "minimal UCI text parser missing"
grep -q 'load_codec_registry("/etc/config/audiowrt-codecs")' audiowrt-dlna/src/renderer-part-01.inc || fail "renderer must load codec registry"
grep -q 'load_player_registry("/etc/config/audiowrt-players")' audiowrt-dlna/src/renderer-part-01.inc || fail "renderer must load player registry"
grep -q 'default_player_' audiowrt-dlna/src/renderer-part-01.inc || fail "DLNA module default player selection missing"
grep -q 'launch_next_player' audiowrt-dlna/src/renderer-part-01.inc || fail "player fallback selection missing"
grep -q 'setpgid' audiowrt-dlna/src/renderer-part-01.inc || fail "players must run in their own process group"
grep -q 'execl(p->executable, p->executable, g.uri' audiowrt-dlna/src/renderer-part-01.inc || fail "player URL argument contract missing"
grep -q 'AUDIOWRT_CODEC' audiowrt-dlna/src/renderer-part-01.inc || fail "player codec environment missing"
grep -q 'AUDIOWRT_MIME' audiowrt-dlna/src/renderer-part-01.inc || fail "player MIME environment missing"
grep -q 'signal(SIGHUP, signal_handler)' audiowrt-dlna/src/renderer-part-04.inc || fail "SIGHUP registry reload missing"
grep -q 'notify_service("ConnectionManager")' audiowrt-dlna/src/renderer-part-04.inc || fail "codec reload must notify ConnectionManager"
grep -q 'procd_add_reload_trigger audiowrt-dlna audiowrt-codecs audiowrt-players' audiowrt-dlna/files/audiowrt-dlna.init || fail "renderer must reload on module and registry UCI changes"

grep -q 'avtransport_action_changes_state' audiowrt-dlna/src/renderer-part-03d.inc || fail "AVTransport state-change event filter missing"
grep -q 'rendering_action_changes_state' audiowrt-dlna/src/renderer-part-03d.inc || fail "RenderingControl state-change event filter missing"
if grep -Fq 'handle_avtransport(fd, action, body); notify_service("AVTransport");' audiowrt-dlna/src/renderer-part-03d.inc; then
  fail "AVTransport SOAP reads must not notify subscribers unconditionally"
fi
if grep -Fq 'handle_rendering(fd, action, body); notify_service("RenderingControl");' audiowrt-dlna/src/renderer-part-03d.inc; then
  fail "RenderingControl SOAP reads must not notify subscribers unconditionally"
fi

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

registry=libaudiowrt-player/files/audiowrt-playback-registry
grep -q 'CODECS_CONFIG=audiowrt-codecs' "$registry" || fail "registry must own separate codec catalog"
grep -q 'PLAYERS_CONFIG=audiowrt-players' "$registry" || fail "registry must own separate player catalog"
grep -Fq 'add_list_value "$CODECS_CONFIG" "$codec" mime "$item"' "$registry" || fail "registry must merge MIME values"
grep -Fq 'add_list_value "$CODECS_CONFIG" "$codec" extension "$item"' "$registry" || fail "registry must merge extensions"
grep -Fq 'add_list_value "$PLAYERS_CONFIG" "$player" codec "$codec"' "$registry" || fail "registry must attach codecs to players"
grep -q 'reload_consumers' "$registry" || fail "registry changes must hot-reload consumers"
grep -q 'audiowrt-renderer audiowrt-local-player' "$registry" || fail "registry reload must be consumer-neutral"
if sed -n '/^register_player()/,/^unregister_player()/p' "$registry" | grep -q 'default_player'; then
  fail "player registration must not create module defaults"
fi

grep -q '+libuclient' libaudiowrt-player/Makefile || fail "player library must depend on libuclient"
grep -q '+alsa-lib' libaudiowrt-player/Makefile || fail "player library must depend on ALSA"
grep -q 'uclient_new' libaudiowrt-player/src/audiowrt-player.c || fail "player library must use libuclient directly"

if grep -REn 'execl.*(wget|uclient-fetch|curl)|system.*(wget|uclient-fetch|curl)' \
  libaudiowrt-player/src audiowrt-player-flac/src audiowrt-player-mp3/src \
  audiowrt-player-aac/src audiowrt-player-wav/src audiowrt-player-vorbis/src; then
  fail "official players must not spawn an external HTTP client"
fi

check_player() {
  local codec="$1" lib="$2" binary="audiowrt-player-$1"
  [[ -f "$binary/Makefile" ]] || fail "$binary Makefile missing"
  [[ -f "$binary/src/$binary.c" ]] || fail "$binary source missing"
  [[ -f "$binary/files/$codec.defaults" ]] || fail "$codec UCI registration script missing"
  [[ ! -e "$binary/files/$codec.conf" ]] || fail "$codec legacy descriptor must be removed"
  grep -q "+libaudiowrt-player" "$binary/Makefile" || fail "$binary must use player library"
  [[ -z "$lib" ]] || grep -q "$lib" "$binary/Makefile" || fail "$binary must depend/link on $lib"
  grep -q "$codec native_$codec" "$binary/files/$codec.defaults" || fail "$codec registry ID mismatch"
  grep -q "/usr/bin/$binary" "$binary/files/$codec.defaults" || fail "$codec executable mismatch"
}

check_player flac libflac
check_player mp3 libmad
check_player aac libfaad2
check_player wav ''
check_player vorbis libvorbis

flac_source="audiowrt-player-flac/src/audiowrt-player-flac.c"
grep -q 'SND_PCM_FORMAT_S16 : SND_PCM_FORMAT_S32' "$flac_source" || fail "FLAC player must use native-endian ALSA PCM formats"
if grep -Eq 'SND_PCM_FORMAT_(S16|S32)_(LE|BE)' "$flac_source"; then
  fail "FLAC player must not hard-code PCM byte order"
fi
if awk '/FLAC__stream_decoder_finish\(decoder\)/ { finished=1 } finished && /fclose\(input\)/ { bad=1 } END { exit bad ? 0 : 1 }' "$flac_source"; then
  fail "FLAC player must not fclose the FILE after libFLAC finish takes ownership"
fi

for source in \
  audiowrt-player-mp3/src/audiowrt-player-mp3.c \
  audiowrt-player-aac/src/audiowrt-player-aac.c \
  audiowrt-player-wav/src/audiowrt-player-wav.c \
  audiowrt-player-vorbis/src/audiowrt-player-vorbis.c; do
  grep -q 'SND_PCM_FORMAT_S16' "$source" || grep -q 'SND_PCM_FORMAT_S32' "$source" || fail "$source must use native PCM format"
done

grep -q '^PKG_NAME:=luci-app-audiowrt-renderer$' luci-app-audiowrt-dlna/Makefile || fail "LuCI package name mismatch"
[[ -f luci-app-audiowrt-dlna/root/usr/share/luci/menu.d/luci-app-audiowrt-dlna.json ]] || fail "LuCI menu missing"
[[ -f luci-app-audiowrt-dlna/root/usr/share/rpcd/acl.d/luci-app-audiowrt-dlna.json ]] || fail "LuCI ACL missing"
grep -q "uci.load('audiowrt-codecs')" luci-app-audiowrt-dlna/htdocs/luci-static/resources/view/audiowrt/dlna.js || fail "LuCI must load codec catalog"
grep -q "uci.load('audiowrt-players')" luci-app-audiowrt-dlna/htdocs/luci-static/resources/view/audiowrt/dlna.js || fail "LuCI must load player catalog"
grep -q 'default_player_' luci-app-audiowrt-dlna/htdocs/luci-static/resources/view/audiowrt/dlna.js || fail "LuCI must expose DLNA codec defaults"
grep -q '"audiowrt-codecs"' luci-app-audiowrt-dlna/root/usr/share/rpcd/acl.d/luci-app-audiowrt-dlna.json || fail "LuCI ACL must read codec catalog"
grep -q '"audiowrt-players"' luci-app-audiowrt-dlna/root/usr/share/rpcd/acl.d/luci-app-audiowrt-dlna.json || fail "LuCI ACL must read player catalog"

sh -n audiowrt-dlna/files/audiowrt-dlna.init
sh -n libaudiowrt-player/files/audiowrt-playback-registry
sh -n libaudiowrt-player/files/audiowrt-player-registry
sh -n libaudiowrt-player/files/audiowrt-playback-registry-migrate
for defaults in audiowrt-player-{flac,mp3,aac,wav,vorbis}/files/*.defaults; do
  sh -n "$defaults"
done

echo "native renderer/discovery/split playback registry contract OK"
