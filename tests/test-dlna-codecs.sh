#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

fail() { echo "DLNA codec contract failed: $*" >&2; exit 1; }

renderer="audiowrt-dlna/src/renderer-part-01.inc"

grep -q 'AUDIOWRT_METADATA' "$renderer" || fail "renderer does not pass DLNA metadata to players"
grep -q 'Prefer an explicit URI extension' "$renderer" || fail "renderer does not prefer explicit extensions"

for package in lpcm m4a aiff opus; do
    test -f "audiowrt-player-$package/Makefile" || fail "$package package missing"
    test -f "audiowrt-player-$package/src/audiowrt-player-$package.c" || fail "$package source missing"
    test -f "audiowrt-player-$package/files/$package.defaults" || fail "$package registration missing"
    grep -q "+libaudiowrt-player" "audiowrt-player-$package/Makefile" ||
        fail "$package does not use shared player library"
done

grep -q 'audio/L16' audiowrt-player-lpcm/files/lpcm.defaults || fail "LPCM MIME missing"
grep -q 'AUDIOWRT_METADATA' audiowrt-player-lpcm/src/audiowrt-player-lpcm.c ||
    fail "LPCM does not use rate/channel metadata"
grep -q 'SND_PCM_FORMAT_S16' audiowrt-player-lpcm/src/audiowrt-player-lpcm.c ||
    fail "LPCM PCM format missing"

grep -q '+faad2' audiowrt-player-m4a/Makefile || fail "M4A must use FAAD frontend"
grep -q '/tmp/audiowrt/m4a-' audiowrt-player-m4a/src/audiowrt-player-m4a.c ||
    fail "M4A seekable staging is not tmpfs"
grep -q '/usr/bin/faad' audiowrt-player-m4a/src/audiowrt-player-m4a.c ||
    fail "M4A FAAD backend missing"
if grep -Eq '(/etc/|/root/|/overlay/).*m4a' audiowrt-player-m4a/src/audiowrt-player-m4a.c; then
    fail "M4A temporary media may touch persistent storage"
fi

grep -q 'memcmp(hdr + 8, "AIFF", 4)' audiowrt-player-aiff/src/audiowrt-player-aiff.c ||
    fail "AIFF container parser missing"
grep -q 'audio/aiff' audiowrt-player-aiff/files/aiff.defaults || fail "AIFF MIME missing"

grep -q '+libopusfile' audiowrt-player-opus/Makefile || fail "Opus library dependency missing"
grep -q 'op_open_callbacks' audiowrt-player-opus/src/audiowrt-player-opus.c ||
    fail "Opus streaming callback path missing"
grep -q 'op_read_stereo' audiowrt-player-opus/src/audiowrt-player-opus.c ||
    fail "Opus decoder path missing"

test -f audiowrt-player-ffmpeg/Makefile || fail "FFmpeg compatibility player missing"
grep -q '+ffmpeg' audiowrt-player-ffmpeg/Makefile || fail "FFmpeg runtime dependency missing"
grep -q 'alac ffmpeg_audio' audiowrt-player-ffmpeg/files/ffmpeg.defaults ||
    fail "ALAC registration missing"
grep -q 'wma ffmpeg_audio' audiowrt-player-ffmpeg/files/ffmpeg.defaults ||
    fail "WMA registration missing"
grep -q 'm4a ffmpeg_audio' audiowrt-player-ffmpeg/files/ffmpeg.defaults ||
    fail "M4A FFmpeg fallback missing"

for defaults in     audiowrt-player-lpcm/files/lpcm.defaults     audiowrt-player-m4a/files/m4a.defaults     audiowrt-player-aiff/files/aiff.defaults     audiowrt-player-opus/files/opus.defaults     audiowrt-player-ffmpeg/files/ffmpeg.defaults; do
    sh -n "$defaults"
done

echo "DLNA codec compatibility contract OK"
