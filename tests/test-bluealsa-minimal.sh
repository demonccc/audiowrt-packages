#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makefile="$repo_root/bluez-alsa/Makefile"
patch="$repo_root/bluez-alsa/patches/005-fix-gcc14-musl-basename.patch"

# GCC 14 + musl rejects the legacy basename() declaration used by BlueALSA 4.1.1.
grep -q '^+#include <libgen.h>$' "$patch"

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

echo 'Minimal BlueALSA build contract tests passed.'
