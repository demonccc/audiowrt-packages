#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-package-context.sh --package NAME --release VERSION --arch ARCH \
  --target TARGET --subtarget SUBTARGET --output DIR [--jobs N] [--cache DIR]

Build exactly one AudioWRT package source in one OpenWrt build context.
This is a compatibility wrapper around build-package-batch.sh so SDK/feed
preparation has one implementation only.
EOF
}

package=""; release=""; arch=""; target=""; subtarget=""; output=""; jobs=4; cache=".cache/audiowrt-packages"
while (($#)); do
  case "$1" in
    --package) package="$2"; shift 2 ;;
    --release) release="$2"; shift 2 ;;
    --arch) arch="$2"; shift 2 ;;
    --target) target="$2"; shift 2 ;;
    --subtarget) subtarget="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --jobs) jobs="$2"; shift 2 ;;
    --cache) cache="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for value in package release arch target subtarget output; do
  [[ -n "${!value}" ]] || { echo "ERROR: --${value//_/-} is required" >&2; exit 2; }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_abs="$(mkdir -p "$output" && cd "$output" && pwd)"
batch_root="$(mktemp -d)"
trap 'rm -rf "$batch_root"' EXIT

tasks_json="$(python3 - "$package" "$target" "$subtarget" <<'PY'
import json, sys
package, target, subtarget = sys.argv[1:]
print(json.dumps([{
    'package': package,
    'scope': 'arch',
    'target': target,
    'subtarget': subtarget,
}], separators=(',', ':')))
PY
)"

bash "$repo_root/scripts/build-package-batch.sh" \
  --release "$release" \
  --arch "$arch" \
  --tasks-json "$tasks_json" \
  --output "$batch_root" \
  --jobs "$jobs" \
  --cache "$cache"

source_path="$batch_root/$package/$release/$arch/$target/$subtarget"
[[ -d "$source_path" ]] || {
  echo "ERROR: batch builder produced no output for $package" >&2
  exit 6
}

rm -rf "$output_abs/packages"
mkdir -p "$output_abs/packages"
cp -f "$source_path"/packages/*.apk "$output_abs/packages/"
cp -f "$source_path/context.json" "$output_abs/context.json"

printf 'Built %s for OpenWrt %s / %s / %s/%s\n' "$package" "$release" "$arch" "$target" "$subtarget"
