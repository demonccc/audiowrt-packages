#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

declare -A canonical=(
  [audiowrt-busybox]='$(TOPDIR)/feeds/base/utils/busybox/Makefile'
  [audiowrt-minimal-alsa]='$(TOPDIR)/feeds/packages/libs/alsa-lib/Makefile'
  [audiowrt-minimal-mbedtls]='$(TOPDIR)/feeds/base/libs/mbedtls/Makefile'
  [audiowrt-dropbear]='$(TOPDIR)/feeds/base/network/services/dropbear/Makefile'
  [audiowrt-minidlna]='$(TOPDIR)/feeds/packages/multimedia/minidlna/Makefile'
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

  # Upstream source identity is owned by the selected OpenWrt recipe. A derived
  # AudioWRT package must never pin its own upstream version/source/hash/date.
  if grep -Eq '^PKG_(VERSION|SOURCE|HASH|MIRROR_HASH|SOURCE_VERSION|SOURCE_DATE)[[:space:]]*[:?+]?=' "$makefile"; then
    echo "ERROR: $package pins upstream source metadata instead of inheriting OpenWrt." >&2
    exit 1
  fi

  # Any AudioWRT source patch is additive and uses the 9xx namespace. OpenWrt
  # patch names must never be copied into the AudioWRT feed.
  while IFS= read -r patch; do
    name="$(basename "$patch")"
    [[ "$name" =~ ^9[0-9][0-9]- ]] || {
      echo "ERROR: derived package carries non-AudioWRT patch: $patch" >&2
      exit 1
    }
  done < <(find "$repo_root/$package" -type f -path '*/patches/*.patch' -print)
done

# The helper must inherit the canonical preamble and canonical patch/file sets,
# while allowing release-family-specific AudioWRT deltas when OpenWrt package
# interfaces differ between 24.10, 25.12, snapshot, etc.
grep -Fq 'include $(AUDIOWRT_DERIVED_PREAMBLE)' "$repo_root/include/audiowrt-openwrt-derived.mk"
grep -Fq -- '-include $(AUDIOWRT_DERIVED_RELEASE_RECIPE)' "$repo_root/include/audiowrt-openwrt-derived.mk"
grep -Fq 'AUDIOWRT_CANONICAL_RECIPE_RESOLVED' "$repo_root/include/audiowrt-openwrt-derived.mk"
grep -Fq '$(TOPDIR)/package/%' "$repo_root/include/audiowrt-openwrt-derived.mk"
grep -Fq "'\$(TOPDIR)'" "$repo_root/include/audiowrt-openwrt-derived.mk"
if grep -Fq './scripts/feeds update base' "$repo_root/include/audiowrt-openwrt-derived.mk"; then
  echo 'ERROR: derived package helper must never materialize the base feed.' >&2
  exit 1
fi
grep -Fq 'copy_tree(canonical_root / "patches", patch_dir)' "$repo_root/scripts/prepare-openwrt-derived.py"
grep -Fq 'copy_tree(canonical_root / "files", files_dir)' "$repo_root/scripts/prepare-openwrt-derived.py"
grep -Fq 'release_delta / "recipe.mk"' "$repo_root/scripts/prepare-openwrt-derived.py"

# `scripts/feeds update` evaluates package Makefiles before VERSION_NUMBER is
# initialized. Verify that an empty make variable is resolved from the exact
# selected tree/SDK's include/version.mk rather than from an AudioWRT default.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/openwrt/include" "$tmp/canonical/patches" "$tmp/delta"
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
python3 "$repo_root/scripts/prepare-openwrt-derived.py" \
  "$tmp/canonical/Makefile" \
  "$tmp/delta" \
  '' \
  "$tmp/openwrt" \
  "$tmp/out/preamble.mk" \
  "$tmp/out/release.mk" \
  "$tmp/out/patches" \
  "$tmp/out/files" \
  "$tmp/out/prepared"
grep -Fq 'openwrt_version=25.12.5' "$tmp/out/prepared"
grep -Fq 'release_family=25.12' "$tmp/out/prepared"

# These use other provenance strategies and must stay release-context aware:
# selector -> exact SDK package; prebuilt -> exact target kmods.
grep -Fq '+wpa-supplicant-mbedtls' "$repo_root/audiowrt-wpa-supplicant/Makefile"
grep -Fq 'Repackages the exact-release OpenWrt Bluetooth core' "$repo_root/audiowrt-kmod-bluetooth/Makefile"
grep -Fq 'Repackages the exact-release ALSA kernel core' "$repo_root/packages/audiowrt-kmod-sound-core/Makefile"
grep -Fq 'exact-release' "$repo_root/packages/audiowrt-kmod-usb-audio/Makefile"

# Packages that have no canonical OpenWrt recipe remain AudioWRT-owned source
# packages; they still compile against the selected SDK/target/toolchain.
test -f "$repo_root/bluez-alsa/Makefile"
test -f "$repo_root/librespot/Makefile"

echo 'OpenWrt-derived package provenance contract passed.'
