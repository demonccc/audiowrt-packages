#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-package-context.sh --package NAME --release VERSION --arch ARCH \
  --target TARGET --subtarget SUBTARGET --output DIR [--jobs N] [--cache DIR]

Build one package by delegating compilation to the canonical AudioWRT package
builder. Selection is release + architecture + target/subtarget only; firmware
profiles, devices and flavors are not part of this flow.
EOF
}

package=""
release=""
arch=""
target=""
subtarget=""
output=""
jobs=4
cache=""

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
engine="${AUDIOWRT_ENGINE_DIR:-}"
[[ -n "$engine" ]] || { echo "ERROR: AUDIOWRT_ENGINE_DIR is required" >&2; exit 3; }
engine="$(cd "$engine" && pwd)"
[[ -f "$engine/Makefile" && -f "$engine/scripts/build.sh" ]] || {
  echo "ERROR: invalid AudioWRT build engine: $engine" >&2
  exit 3
}

source_dir=""
for category in audiowrt ported trimmed tailored; do
  while IFS= read -r makefile; do
    if grep -Eq "^define (Package/${package}|KernelPackage/${package#kmod-})([[:space:]]|$)" "$makefile"; then
      source_dir="$(dirname "$makefile")"
      break 2
    fi
  done < <(find "$repo_root/$category" -mindepth 2 -maxdepth 2 -name Makefile -type f | sort)
done
[[ -n "$source_dir" ]] || { echo "ERROR: unknown AudioWRT package source: $package" >&2; exit 3; }

mkdir -p "$output/packages"
output="$(cd "$output" && pwd)"
packages_ref="$(git -C "$repo_root" rev-parse HEAD)"

cache_arg=""
if [[ -n "$cache" ]]; then
  mkdir -p "$cache"
  cache="$(cd "$cache" && pwd)"
  case "$cache" in
    "$engine"/*) cache_arg="${cache#"$engine"/}" ;;
    *)
      echo "ERROR: canonical builder cache must live inside the AudioWRT engine checkout: $cache" >&2
      exit 3
      ;;
  esac
fi

make -C "$engine" packages \
  OPENWRT_VERSION="$release" \
  TARGET="$target" \
  SUBTARGET="$subtarget" \
  ARCH="$arch" \
  PACKAGE="$package" \
  AUDIOWRT_PACKAGES_REF="$packages_ref" \
  JOBS="$jobs" \
  CACHE_DIR="$cache_arg"

engine_output="$engine/output/packages/package-context-$release/packages"
[[ -d "$engine_output" ]] || {
  echo "ERROR: canonical AudioWRT builder produced no package directory: $engine_output" >&2
  exit 6
}

mapfile -t output_names < <(python3 - "$source_dir/Makefile" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
for name in re.findall(r'^define Package/([^\s]+)', text, re.M):
    print(name)
for name in re.findall(r'^define KernelPackage/([^\s]+)', text, re.M):
    print('kmod-' + name)
PY
)

found=0
for name in "${output_names[@]}"; do
  while IFS= read -r apk; do
    cp -f "$apk" "$output/packages/"
    found=1
  done < <(find "$engine_output" -maxdepth 1 -type f -name "$name-*.apk" -print)
done
[[ "$found" == 1 ]] || {
  echo "ERROR: canonical AudioWRT builder produced no root APK for $package" >&2
  exit 6
}

python3 - "$output/context.json" "$package" "$release" "$arch" "$target" "$subtarget" <<'PY'
import json, sys
path, package, release, arch, target, subtarget = sys.argv[1:]
with open(path, 'w', encoding='utf-8') as handle:
    json.dump({
        'package_source': package,
        'openwrt_version': release,
        'arch': arch,
        'target': target,
        'subtarget': subtarget,
        'builder': 'demonccc/audiowrt',
    }, handle, indent=2, sort_keys=True)
    handle.write('\n')
PY

printf 'Built %s for OpenWrt %s / %s / %s/%s with canonical AudioWRT builder\n' \
  "$package" "$release" "$arch" "$target" "$subtarget"
