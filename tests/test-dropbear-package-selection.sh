#!/usr/bin/env bash
set -euo pipefail

makefile="$(dirname "$0")/../audiowrt-dropbear/Makefile"

grep -q 'PROVIDES:=dropbear' "$makefile"
if grep -q 'CONFLICTS:=dropbear' "$makefile"; then
    echo 'audiowrt-dropbear must not declare a build-time conflict with the SDK dropbear symbol; the firmware profile removes the stock package explicitly.' >&2
    exit 1
fi

echo 'Dropbear package selection contract passed.'
