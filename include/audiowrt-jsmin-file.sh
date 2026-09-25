#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

jsmin="$1"
src="$2"
tmp="${src}.min"

trap 'rm -f "$tmp"' EXIT HUP INT TERM
"$jsmin" < "$src" > "$tmp"
mv -f "$tmp" "$src"
trap - EXIT HUP INT TERM
