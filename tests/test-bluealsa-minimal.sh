#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makefile="$repo_root/bluez-alsa/Makefile"
alsa_makefile="$repo_root/audiowrt-minimal-alsa/Makefile"
patch="$repo_root/bluez-alsa/patches/005-fix-gcc14-musl-basename.patch"
ctl_helper="$repo_root/bluez-alsa/files/disable-ctl.py"

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
grep -Fq 'PATH="$(PKG_BUILD_DIR)/host-tools:$$$$PATH"' "$makefile" || {
    echo 'ERROR: BlueALSA host PATH must survive OpenWrt double make expansion.' >&2
    exit 1
}
python3 "$repo_root/bluez-alsa/files/gdbus-codegen/gdbus-codegen" --help >/dev/null

grep -q 'AC_ARG_ENABLE(\[ctl\]' "$ctl_helper"
grep -q 'AM_CONDITIONAL(\[ENABLE_CTL\]' "$ctl_helper"
grep -q 'if ENABLE_CTL' "$ctl_helper"
grep -q 'disable-ctl.py' "$makefile"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/src/asound"
cat >"$tmp/configure.ac" <<'EOF'
AC_PATH_PROGS([GDBUS_CODEGEN], [gdbus-codegen])
AS_IF([test "x$GDBUS_CODEGEN" = "x"], [AC_MSG_ERROR([[gdbus-codegen not found]])])

PKG_CHECK_MODULES([LIBBSD], [libbsd >= 0.8],
EOF
cat >"$tmp/src/asound/Makefile.am" <<'EOF'
asound_module_ctl_LTLIBRARIES = libasound_module_ctl_bluealsa.la
asound_module_pcm_LTLIBRARIES = libasound_module_pcm_bluealsa.la
EOF
python3 "$ctl_helper" "$tmp"
python3 "$ctl_helper" "$tmp"
grep -q 'AC_ARG_ENABLE(\[ctl\]' "$tmp/configure.ac"
grep -q '^if ENABLE_CTL
# The 8 MB baseline only needs the A2DP Source path. Do not build receiver-side
# utilities or optional codecs/tools that increase compile and firmware size.
for option in \
    --disable-aplay \
    --disable-cli \
    --disable-ctl \
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
grep -q 'libasound_module_pcm_bluealsa.so' "$makefile"
if grep -q 'libasound_module_\*_bluealsa' "$makefile"; then
    echo 'ERROR: BlueALSA install must not wildcard-install the control plugin.' >&2
    exit 1
fi

# BlueALSA now exposes only the PCM plugin. ioplug is required; the external
# ALSA control plugin is not part of the AudioWRT runtime path.
grep -q -- '--with-pcm-plugins=.*ioplug' "$alsa_makefile"

echo 'Minimal BlueALSA build contract tests passed.'
 "$tmp/src/asound/Makefile.am"

# The 8 MB baseline only needs the A2DP Source path. Do not build receiver-side
# utilities or optional codecs/tools that increase compile and firmware size.
for option in \
    --disable-aplay \
    --disable-cli \
    --disable-ctl \
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
grep -q 'libasound_module_pcm_bluealsa.so' "$makefile"
if grep -q 'libasound_module_\*_bluealsa' "$makefile"; then
    echo 'ERROR: BlueALSA install must not wildcard-install the control plugin.' >&2
    exit 1
fi

# BlueALSA now exposes only the PCM plugin. ioplug is required; the external
# ALSA control plugin is not part of the AudioWRT runtime path.
grep -q -- '--with-pcm-plugins=.*ioplug' "$alsa_makefile"

echo 'Minimal BlueALSA build contract tests passed.'
