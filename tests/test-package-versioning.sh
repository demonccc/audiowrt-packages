#!/usr/bin/env bash
set -euo pipefail

fail() { echo "package versioning contract failed: $*" >&2; exit 1; }

while IFS= read -r makefile; do
    name="$(sed -n 's/^PKG_NAME:=//p' "$makefile" | head -n 1)"
    [[ -n "$name" ]] || continue

    case "$name" in
        audiowrt-*|libaudiowrt-*|luci-app-audiowrt-*) ;;
        *) continue ;;
    esac

    # OpenWrt-derived recipes inherit the selected release's upstream version.
    grep -q '^AUDIOWRT_CANONICAL_RECIPE:=' "$makefile" && continue

    # Kernel packages are versioned by the OpenWrt kernel ABI/release machinery.
    grep -q 'KernelPackage/' "$makefile" && continue

    version="$(sed -n 's/^PKG_VERSION:=//p' "$makefile" | head -n 1)"
    release="$(sed -n 's/^PKG_RELEASE:=//p' "$makefile" | head -n 1)"

    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        fail "$name must declare semantic PKG_VERSION (found '${version:-missing}')"
    [[ "$release" =~ ^[0-9]+$ ]] ||
        fail "$name must declare numeric PKG_RELEASE (found '${release:-missing}')"
done < <(find . -mindepth 2 -maxdepth 3 -name Makefile -type f | sort)

echo "AudioWRT package versioning contract OK"
