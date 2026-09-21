#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

fail() { echo "playback registry contract failed: $*" >&2; exit 1; }

registry="libaudiowrt-player/files/audiowrt-playback-registry"
compat="libaudiowrt-player/files/audiowrt-player-registry"
renderer="audiowrt-dlna/src/renderer-part-01.inc"
dlna_ui="luci-app-audiowrt-dlna/htdocs/luci-static/resources/view/audiowrt/dlna.js"

[[ -f "$registry" ]] || fail "playback registry helper missing"
[[ -f libaudiowrt-player/files/audiowrt-codecs.config ]] || fail "codec config missing"
[[ -f libaudiowrt-player/files/audiowrt-players.config ]] || fail "player config missing"

grep -Fq 'CODECS_CONFIG=audiowrt-codecs' "$registry" ||
    fail "codec catalog is not separate"
grep -Fq 'PLAYERS_CONFIG=audiowrt-players' "$registry" ||
    fail "player catalog is not separate"

register_block="$(sed -n '/^register_player()/,/^unregister_player()/p' "$registry")"
grep -Fq 'ensure_section "$CODECS_CONFIG" "$codec" codec' <<<"$register_block" ||
    fail "install registration does not create a missing codec"
grep -Fq 'add_list_value "$CODECS_CONFIG" "$codec" mime "$item"' <<<"$register_block" ||
    fail "install registration does not merge MIME types"
grep -Fq 'add_list_value "$CODECS_CONFIG" "$codec" extension "$item"' <<<"$register_block" ||
    fail "install registration does not merge extensions"
grep -Fq 'ensure_section "$PLAYERS_CONFIG" "$player" player' <<<"$register_block" ||
    fail "install registration does not create the player"
grep -Fq 'add_list_value "$PLAYERS_CONFIG" "$player" codec "$codec"' <<<"$register_block" ||
    fail "install registration does not attach codec support"
if grep -q 'default_player' <<<"$register_block"; then
    fail "player installation must not select a module default"
fi

# Codec definitions live while at least one registered player references them.
grep -Fq 'codec_referenced "$codec"' "$registry" ||
    fail "unregister does not protect codecs still used by another player"

# Legacy codec/player sections are migrated away from the AudioWRT core config.
grep -Fq 'LEGACY_CONFIG=audiowrt' "$registry" ||
    fail "legacy registry migration source missing"
grep -Fq 'DLNA_CONFIG=audiowrt-dlna' "$registry" ||
    fail "legacy DLNA defaults are not migrated into the DLNA module"

# DLNA consumes the shared catalogs but owns its own preferred player choices.
grep -Fq 'load_codec_registry("/etc/config/audiowrt-codecs")' "$renderer" ||
    fail "DLNA does not read the shared codec catalog"
grep -Fq 'load_player_registry("/etc/config/audiowrt-players")' "$renderer" ||
    fail "DLNA does not read the shared player catalog"
grep -Fq 'default_player_' "$renderer" ||
    fail "DLNA does not read module-local player defaults"
grep -Fq "new form.Map('audiowrt-dlna'" "$dlna_ui" ||
    fail "DLNA UI does not save defaults in the DLNA module"
grep -Fq "uci.load('audiowrt-codecs')" "$dlna_ui" ||
    fail "DLNA UI does not read codec catalog"
grep -Fq "uci.load('audiowrt-players')" "$dlna_ui" ||
    fail "DLNA UI does not read player catalog"

# Every installed AudioWRT codec player registers itself through the generic helper.
for package in flac mp3 aac wav vorbis lpcm m4a aiff opus ffmpeg; do
    makefile="audiowrt-player-$package/Makefile"
    defaults="audiowrt-player-$package/files/$package.defaults"
    grep -Fq '/usr/libexec/audiowrt-playback-registry register' "$makefile" ||
        fail "$package postinst does not register through playback registry"
    grep -Fq '/usr/libexec/audiowrt-playback-registry unregister' "$makefile" ||
        fail "$package prerm does not unregister through playback registry"
    grep -Fq '/usr/libexec/audiowrt-playback-registry register' "$defaults" ||
        fail "$package first-install defaults do not register through playback registry"
    if grep -q 'default_player' "$makefile" "$defaults"; then
        fail "$package installation must not write a module default"
    fi
done

grep -Fq 'exec /usr/libexec/audiowrt-playback-registry "$@"' "$compat" ||
    fail "old registry helper is not a compatibility alias"

sh -n "$registry"
sh -n "$compat"
sh -n libaudiowrt-player/files/audiowrt-playback-registry-migrate

echo "Split codec/player registration contract OK"
