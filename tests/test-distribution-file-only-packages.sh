#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for package in \
    audiowrt-core \
    audiowrt-provisioning \
    audiowrt-storage \
    luci-app-audiowrt-core \
    luci-app-audiowrt-storage; do
    makefile="$repo_root/$package/Makefile"
    for phase in Prepare Configure Compile; do
        grep -q "^define Build/$phase$" "$makefile" || {
            echo "ERROR: missing explicit Build/$phase in file-only distribution package: $package" >&2
            exit 1
        }
    done
done

printf 'Distribution file-only package tests passed.\n'
