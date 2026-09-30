#!/usr/bin/env bash
set -euo pipefail

fail() { echo "package versioning contract failed: $*" >&2; exit 1; }

while IFS= read -r makefile; do
    name="$(sed -n 's/^PKG_NAME:=//p' "$makefile" | head -n 1)"
    derived="$(sed -n 's/^AUDIOWRT_DERIVED_NAME:=//p' "$makefile" | head -n 1)"
    repackage_version_source="$(sed -n 's/^AUDIOWRT_REPACKAGE_VERSION_SOURCE:=//p' "$makefile" | head -n 1)"
    [[ -n "$name" || -n "$derived" ]] || continue

    release="$(sed -n 's/^PKG_RELEASE:=//p' "$makefile" | head -n 1)"

    # Source-derived packages inherit PKG_VERSION from the selected OpenWrt
    # recipe. Kernel packages are versioned by the OpenWrt kernel ABI.
    if [[ -n "$derived" ]]; then
        [[ -z "$release" || "$release" =~ ^[1-9][0-9]*$ ]] || fail "$derived has invalid packaging revision"
        ! grep -q '^PKG_VERSION:=' "$makefile" || fail "$derived must inherit upstream source version"
        continue
    fi

    # Binary repackages preserve the exact official OpenWrt payload and inherit
    # the upstream version from the selected release recipe instead of pinning
    # a second source version in AudioWRT.
    if [[ -n "$repackage_version_source" ]]; then
        [[ "$repackage_version_source" == '$(TOPDIR)/feeds/'*'/Makefile' ]] ||
            fail "$name has invalid AUDIOWRT_REPACKAGE_VERSION_SOURCE '$repackage_version_source'"
        [[ -z "$release" || "$release" =~ ^[1-9][0-9]*$ ]] ||
            fail "$name has invalid packaging revision"
        version="$(sed -n 's/^PKG_VERSION:=//p' "$makefile" | head -n 1)"
        [[ "$version" == *'$(AUDIOWRT_REPACKAGE_VERSION_SOURCE)'* ]] ||
            fail "$name must inherit PKG_VERSION from AUDIOWRT_REPACKAGE_VERSION_SOURCE"
        continue
    fi

    # Kernel packages are versioned by the OpenWrt kernel ABI/release machinery.
    grep -q 'KernelPackage/' "$makefile" && continue

    version="$(sed -n 's/^PKG_VERSION:=//p' "$makefile" | head -n 1)"

    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        fail "$name must declare semantic PKG_VERSION (found '${version:-missing}')"
    [[ -z "$release" || "$release" =~ ^[1-9][0-9]*$ ]] ||
        fail "$name has invalid PKG_RELEASE '${release}'"
done < <(find . -mindepth 2 -maxdepth 3 -name Makefile -type f | sort)

echo "AudioWRT package versioning contract OK"
