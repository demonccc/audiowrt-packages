#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makefile="$repo_root/bluez-alsa/Makefile"
alsa_makefile="$repo_root/audiowrt-minimal-alsa/Makefile"
patch="$repo_root/bluez-alsa/patches/005-fix-gcc14-musl-basename.patch"

# GCC 14 + musl rejects the legacy basename() declaration used by BlueALSA 4.1.1.
grep -q '^+#include <libgen.h>$' "$patch"

# BlueALSA needs gdbus-codegen only as a host-side source generator. Keep a
# vendored Python copy so building the minimal Bluetooth stack never compiles
# glib2/host and its PCRE/libffi/iconv host dependency chain.
if grep -q '^PKG_BUILD_DEPENDS:=glib2/host$' "$makefile"; then
    echo 'ERROR: minimal BlueALSA must not build glib2 host tools.' >&2
    exit 1
fi
grep -q 'files/gdbus-codegen' "$makefile"
grep -q 'GDBUS_CODEGEN=' "$makefile"
python3 "$repo_root/bluez-alsa/files/gdbus-codegen/gdbus-codegen" --help >/dev/null

# The 8 MB baseline only needs the A2DP Source path. Do not build receiver-side
# utilities or optional codecs/tools that increase compile and firmware size.
for option in \
    --disable-aplay \
    --disable-cli \
    --disable-rfcomm \
    --disable-hcitop \
    --disable-manpages \
    --disable-test \
    --disable-aac \
    --disable-aptx \
    --disable-aptx-hd \
    --disable-ldac \
    --disable-mp3lame \
    --disable-mpg123 \
    --disable-msbc; do
    grep -q -- "$option" "$makefile"
done

if grep -q 'bluealsa-aplay.*usr/bin' "$makefile"; then
    echo 'ERROR: bluealsa-aplay must not be installed in the A2DP Source baseline.' >&2
    exit 1
fi

grep -q 'src/bluealsa.*usr/bin/bluealsa' "$makefile"
grep -q 'libasound_module_.*_bluealsa' "$makefile"

# BlueALSA builds external PCM and control plugins. Its PCM implementation uses
# ALSA ioplug and its control implementation uses the external control API.
grep -q -- '--with-pcm-plugins=.*ioplug' "$alsa_makefile"
grep -q -- '--with-ctl-plugins=ext' "$alsa_makefile"

echo 'Minimal BlueALSA build contract tests passed.'
