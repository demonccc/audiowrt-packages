#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

declare -A canonical=(
  [audiowrt-busybox]='$(TOPDIR)/feeds/base/utils/busybox/Makefile'
  [libaudiowrt-alsa-minimal]='$(TOPDIR)/feeds/packages/libs/alsa-lib/Makefile'
  [audiowrt-wpad]='$(TOPDIR)/feeds/base/network/services/hostapd/Makefile'
  [audiowrt-umdns]='$(TOPDIR)/feeds/base/network/services/umdns/Makefile'
  [audiowrt-sbc]='$(TOPDIR)/feeds/packages/libs/sbc/Makefile'
  [audiowrt-bluez]='$(TOPDIR)/feeds/packages/utils/bluez/Makefile'
)

for package in "${!canonical[@]}"; do
  makefile="$repo_root/$package/Makefile"
  test -f "$makefile"
  grep -Fq "AUDIOWRT_DERIVED_NAME:=$package" "$makefile"
  grep -Fq "AUDIOWRT_CANONICAL_RECIPE:=${canonical[$package]}" "$makefile"
  grep -Fq 'include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk' "$makefile"

  if grep -Eq '^PKG_(VERSION|SOURCE|HASH|MIRROR_HASH|SOURCE_VERSION|SOURCE_DATE)[[:space:]]*[:?+]?=' "$makefile"; then
    echo "ERROR: $package pins upstream source metadata instead of inheriting OpenWrt." >&2
    exit 1
  fi

  while IFS= read -r patch; do
    name="$(basename "$patch")"
    [[ "$name" =~ ^9[0-9][0-9]- ]] || {
      echo "ERROR: derived package carries non-AudioWRT patch: $patch" >&2
      exit 1
    }
  done < <(find "$repo_root/$package" -type f -path '*/patches/*.patch' -print)
done

helper="$repo_root/include/audiowrt-openwrt-derived.mk"
grep -Fq 'include $(AUDIOWRT_DERIVED_PREAMBLE)' "$helper"
grep -Fq -- '-include $(AUDIOWRT_DERIVED_RELEASE_RECIPE)' "$helper"
grep -Fq 'AUDIOWRT_CANONICAL_RECIPE_RESOLVED' "$helper"
grep -Fq '$(TOPDIR)/package/%' "$helper"
grep -Fq 'materialize-openwrt-base.py' "$helper"
grep -Fq "'\$(TOPDIR)'" "$helper"
if grep -Fq './scripts/feeds update base' "$helper"; then
  echo 'ERROR: package Makefiles must never recursively index the base feed.' >&2
  exit 1
fi

grep -Fq 'copy_tree(canonical_root / "patches", patch_dir)' "$repo_root/scripts/prepare-openwrt-derived.py"
grep -Fq 'copy_tree(canonical_root / "files", files_dir)' "$repo_root/scripts/prepare-openwrt-derived.py"
grep -Fq 'copy_tree(canonical_root / "src", src_dir)' "$repo_root/scripts/prepare-openwrt-derived.py"
grep -Fq 'AUDIOWRT_DERIVED_SRC_DIR' "$helper"
grep -Fq 'Build/Prepare/AudioWRTDerived' "$helper"
grep -Fq 'release_delta / "recipe.mk"' "$repo_root/scripts/prepare-openwrt-derived.py"

# Verify that a missing SDK core source tree can be materialized from the exact
# base feed declaration without invoking OpenWrt feed indexing/install or make.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/upstream/package/utils/busybox" "$tmp/sdk/feeds"
printf 'fixture\n' > "$tmp/upstream/package/utils/busybox/Makefile"
git -C "$tmp/upstream" init -q
git -C "$tmp/upstream" config user.email test@example.invalid
git -C "$tmp/upstream" config user.name test
git -C "$tmp/upstream" add .
git -C "$tmp/upstream" commit -qm fixture
upstream_commit="$(git -C "$tmp/upstream" rev-parse HEAD)"
printf 'src-git --root=package base file://%s^%s\n' "$tmp/upstream" "$upstream_commit" > "$tmp/sdk/feeds.conf"
python3 "$repo_root/scripts/materialize-openwrt-base.py" "$tmp/sdk"
test -L "$tmp/sdk/feeds/base"
test -f "$tmp/sdk/feeds/base/utils/busybox/Makefile"
test "$(git -C "$tmp/sdk/feeds/base_root" rev-parse HEAD)" = "$upstream_commit"
test ! -e "$tmp/sdk/feeds/base.tmp"
test ! -e "$tmp/sdk/feeds/base.index"
# A second invocation must reuse the exact checkout instead of recloning it.
python3 "$repo_root/scripts/materialize-openwrt-base.py" "$tmp/sdk"
test "$(git -C "$tmp/sdk/feeds/base_root" rev-parse HEAD)" = "$upstream_commit"

# `scripts/feeds update` evaluates package Makefiles before VERSION_NUMBER is
# initialized. Verify that an empty make variable is resolved from the exact
# selected tree/SDK's include/version.mk rather than from an AudioWRT default.
mkdir -p "$tmp/openwrt/include" "$tmp/canonical/patches" "$tmp/canonical/src/src/ap" "$tmp/delta"
cat >"$tmp/openwrt/include/version.mk" <<'EOF'
VERSION_NUMBER:=$(call qstrip,$(CONFIG_VERSION_NUMBER))
VERSION_NUMBER:=$(if $(VERSION_NUMBER),$(VERSION_NUMBER),25.12.5)
EOF
cat >"$tmp/canonical/Makefile" <<'EOF'
include $(TOPDIR)/rules.mk
PKG_NAME:=fixture
PKG_VERSION:=1.0
include $(INCLUDE_DIR)/package.mk
EOF
printf 'canonical overlay\n' > "$tmp/canonical/src/src/ap/ubus.h"
python3 "$repo_root/scripts/prepare-openwrt-derived.py" \
  "$tmp/canonical/Makefile" \
  "$tmp/delta" \
  '' \
  "$tmp/openwrt" \
  "$tmp/out/preamble.mk" \
  "$tmp/out/release.mk" \
  "$tmp/out/patches" \
  "$tmp/out/files" \
  "$tmp/out/src" \
  "$tmp/out/prepared"
grep -Fq 'openwrt_version=25.12.5' "$tmp/out/prepared"
grep -Fq 'release_family=25.12' "$tmp/out/prepared"
grep -Fq 'canonical overlay' "$tmp/out/src/src/ap/ubus.h"

# The constrained DLNA renderer is a runtime profile around exact-release
# OpenWrt binaries. It must never become a source-derived package because that
# would recursively build MPD/libupnpp and their dependency graphs.
renderer_makefile="$repo_root/audiowrt-minimal-upmpdcli/Makefile"
grep -Fq 'PKGARCH:=all' "$renderer_makefile"
grep -Fq 'DEPENDS:=+upmpdcli +mpd-mini' "$renderer_makefile"
for phase in Prepare Configure Compile; do
  grep -q "^define Build/$phase$" "$renderer_makefile"
done
if grep -Fq 'audiowrt-openwrt-derived.mk' "$renderer_makefile"; then
  echo 'ERROR: audiowrt-minimal-upmpdcli must reuse official release binaries.' >&2
  exit 1
fi

test ! -e "$repo_root/audiowrt-minimal-mpd/Makefile"
test ! -e "$repo_root/audiowrt-dropbear/Makefile"


grep -Fq 'PROVIDES:=hostapd wpa-supplicant' "$repo_root/audiowrt-wpad/Makefile"
grep -Fq '$(Build/Prepare/AudioWRTDerived)' "$repo_root/audiowrt-wpad/Makefile"
grep -Fq 'hostapd_multi.a' "$repo_root/audiowrt-wpad/Makefile"
grep -Fq 'wpa_supplicant_multi.a' "$repo_root/audiowrt-wpad/Makefile"
if grep -Fq '+wpa-supplicant-mbedtls' "$repo_root/audiowrt-wpad/Makefile"; then
  echo 'ERROR: AudioWRT wpad regressed to the full OpenWrt supplicant metapackage.' >&2
  exit 1
fi
grep -Fq 'Repackages the exact-release OpenWrt Bluetooth core' "$repo_root/audiowrt-kmod-bluetooth/Makefile"
grep -Fq 'Repackages the exact-release ALSA kernel core' "$repo_root/packages/audiowrt-kmod-sound-core/Makefile"
grep -Fq 'exact-release' "$repo_root/packages/audiowrt-kmod-usb-audio/Makefile"

test -f "$repo_root/bluez-alsa/Makefile"
test -f "$repo_root/librespot/Makefile"

echo 'OpenWrt-derived package provenance contract passed.'
