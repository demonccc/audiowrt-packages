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
grep -Fq 'copy_tree(canonical_root / "patches", patch_dir)' "$repo_root/scripts/prepare-openwrt-derived.py"
grep -Fq 'copy_tree(canonical_root / "files", files_dir)' "$repo_root/scripts/prepare-openwrt-derived.py"
grep -Fq 'release_delta / "recipe.mk"' "$repo_root/scripts/prepare-openwrt-derived.py"

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
