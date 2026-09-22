#!/usr/bin/env bash
set -euo pipefail

fail() { echo "package versioning contract failed: $*" >&2; exit 1; }

while IFS= read -r makefile; do
    name="$(sed -n 's/^PKG_NAME:=//p' "$makefile" | head -n 1)"
    derived="$(sed -n 's/^AUDIOWRT_DERIVED_NAME:=//p' "$makefile" | head -n 1)"
    [[ -n "$name" || -n "$derived" ]] || continue

    release="$(sed -n 's/^PKG_RELEASE:=//p' "$makefile" | head -n 1)"

    # Source-derived packages inherit PKG_VERSION from the selected OpenWrt
    # recipe. Kernel packages are versioned by the OpenWrt kernel ABI.
    if [[ -n "$derived" ]]; then
        [[ -z "$release" || "$release" =~ ^[1-9][0-9]*$ ]] || fail "$derived has invalid packaging revision"
        ! grep -q '^PKG_VERSION:=' "$makefile" || fail "$derived must inherit upstream source version"
        continue
    fi

    # Kernel packages are versioned by the OpenWrt kernel ABI/release machinery.
    grep -q 'KernelPackage/' "$makefile" && continue

    version="$(sed -n 's/^PKG_VERSION:=//p' "$makefile" | head -n 1)"

    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        fail "$name must declare semantic PKG_VERSION (found '${version:-missing}')"
    [[ "$release" == 1 ]] ||
        fail "$name must declare PKG_RELEASE:=1 (found '${release:-missing}')"
done < <(find . -mindepth 2 -maxdepth 3 -name Makefile -type f | sort)

echo "AudioWRT package versioning contract OK"
