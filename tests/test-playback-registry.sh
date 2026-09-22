#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
registry=libaudiowrt-player/files/audiowrt-playback-registry
! grep -q 'uci-defaults' libaudiowrt-player/Makefile
! grep -q 'migrate_legacy' "$registry"
grep -q 'work=$(mktemp -d /tmp/audiowrt/registry' "$registry"
grep -q 'command uci -c "$work"' "$registry"
for package in flac mp3 aac wav vorbis lpcm m4a aiff opus ffmpeg; do
    test -f "audiowrt-player-$package/files/$package.manifest"
    grep -q 'playback-registry rebuild' "audiowrt-player-$package/Makefile"
    ! grep -q 'uci-defaults' "audiowrt-player-$package/Makefile"
done
grep -q '/tmp/audiowrt/registry/audiowrt-codecs' libaudiowrt-player/Makefile
sh -n "$registry"
printf 'Volatile playback catalog checks passed.\n'
