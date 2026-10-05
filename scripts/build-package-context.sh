#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-package-context.sh --package NAME --release VERSION --arch ARCH \
  --target TARGET --subtarget SUBTARGET --output DIR [--jobs N] [--cache DIR]

Build one AudioWRT package root in one clean OpenWrt SDK context. AudioWRT-owned
runtime/build dependencies are resolved and compiled first in topological order.
No AudioWRT firmware profile, device or flavor participates in package CI.
EOF
}

package=""
release=""
arch=""
target=""
subtarget=""
output=""
jobs=4
cache="${RUNNER_TEMP:-/tmp}/audiowrt-packages-cache"

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
source_dir=""
for category in audiowrt ported trimmed tailored; do
  candidate="$repo_root/$category/$package"
  if [[ -f "$candidate/Makefile" ]]; then
    source_dir="$candidate"
    break
  fi
done
[[ -n "$source_dir" ]] || { echo "ERROR: unknown AudioWRT package source: $package" >&2; exit 3; }

build_targets="$repo_root/config/build/package-build-targets"
source_build_packages="$repo_root/config/build/source-build-packages"
resolver="$repo_root/scripts/resolve-package-build-targets.py"
[[ -f "$build_targets" ]] || { echo "ERROR: package build target map is missing" >&2; exit 3; }
[[ -f "$resolver" ]] || { echo "ERROR: package dependency resolver is missing" >&2; exit 3; }

is_source_build_package() {
  local name="$1"
  [[ -f "$source_build_packages" ]] || return 1
  grep -Ev '^[[:space:]]*(#|$)' "$source_build_packages" | grep -Fxq "$name"
}

mkdir -p "$cache" "$output/packages"
cache="$(cd "$cache" && pwd)"
output="$(cd "$output" && pwd)"

base_url="https://downloads.openwrt.org/releases/$release/targets/$target/$subtarget"
index="$(curl -fsSL "$base_url/")"
archive="$(printf '%s' "$index" | grep -oE "openwrt-sdk-${release//./\.}-${target//-/_}-${subtarget//-/_}[^\"<> ]*Linux-x86_64\.tar\.(zst|xz)" | head -n1 || true)"
if [[ -z "$archive" ]]; then
  archive="$(printf '%s' "$index" | grep -oE "openwrt-sdk-${release//./\.}-[^\"<> ]*Linux-x86_64\.tar\.(zst|xz)" | head -n1 || true)"
fi
[[ -n "$archive" ]] || { echo "ERROR: unable to discover SDK at $base_url/" >&2; exit 4; }

archive_path="$cache/$archive"
if [[ ! -s "$archive_path" ]]; then
  echo "Downloading $archive"
  curl -fL --retry 3 -o "$archive_path.tmp" "$base_url/$archive"
  mv "$archive_path.tmp" "$archive_path"
fi

# Cache only the immutable SDK archive. Every package root receives a fresh SDK
# workspace so generated Kconfig, package metadata and staging state cannot leak
# between independent package tasks.
sdk_parent="$(mktemp -d "$cache/sdk-work-${release}-${target}-${subtarget}-XXXXXX")"
cleanup() { rm -rf "$sdk_parent"; }
trap cleanup EXIT
case "$archive" in
  *.tar.zst) tar --zstd -xf "$archive_path" -C "$sdk_parent" ;;
  *.tar.xz) tar -xJf "$archive_path" -C "$sdk_parent" ;;
  *) echo "ERROR: unsupported SDK archive: $archive" >&2; exit 4 ;;
esac
sdk="$(find "$sdk_parent" -mindepth 1 -maxdepth 1 -type d | head -n1)"
[[ -n "$sdk" ]] || { echo "ERROR: SDK extraction produced no directory" >&2; exit 4; }

cp "$sdk/feeds.conf.default" "$sdk/feeds.conf"
printf '\nsrc-link audiowrt %s\n' "$repo_root" >> "$sdk/feeds.conf"

(
  cd "$sdk"
  ./scripts/feeds update -a
  ./scripts/feeds install -a
  make defconfig

  packageinfo="$sdk/tmp/.packageinfo"
  [[ -s "$packageinfo" ]] || {
    echo "ERROR: OpenWrt package metadata was not generated" >&2
    exit 5
  }

  build_plan="$sdk/tmp/audiowrt-build-plan.txt"
  python3 "$resolver" "$build_targets" "$packageinfo" "$package" > "$build_plan"
  mapfile -t build_specs < "$build_plan"
  ((${#build_specs[@]})) || {
    echo "ERROR: no AudioWRT build targets resolved for $package" >&2
    exit 5
  }

  echo "AudioWRT dependency closure for $package:"
  printf '  %s\n' "${build_specs[@]}"

  # Compile dependencies first, then the requested root. Package-only recipes
  # stay behind NO_DEPS=1 so official OpenWrt runtime dependencies are not
  # rebuilt. The small explicit source-build set may traverse its development
  # dependency graph (GLib for btctl/BlueZ, Rust for librespot, etc.).
  for spec in "${build_specs[@]}"; do
    build_package="${spec%%|*}"
    target_path="${spec#*|}"
    [[ -n "$build_package" && -n "$target_path" && "$target_path" != "$spec" ]] || {
      echo "ERROR: invalid build plan entry: $spec" >&2
      exit 5
    }
    [[ -e "package/feeds/audiowrt/$build_package" ]] || {
      echo "ERROR: AudioWRT feed did not register source package $build_package" >&2
      exit 5
    }

    if is_source_build_package "$build_package"; then
      echo "Building AudioWRT source dependency/root: $build_package"
      make "$target_path" -j"$jobs" V=s
    else
      echo "Building AudioWRT package-only dependency/root: $build_package (NO_DEPS=1)"
      make "$target_path" NO_DEPS=1 -j"$jobs" V=s
    fi
  done
)

# Publish only APK outputs declared by the requested source root. Dependency APKs
# are internal build inputs for this task; their own planner tasks publish them.
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
  done < <(find "$sdk/bin" -type f -name "$name-*.apk" -print)
done
[[ "$found" == 1 ]] || { echo "ERROR: no APK output found for $package" >&2; exit 6; }

python3 - "$output/context.json" "$package" "$release" "$arch" "$target" "$subtarget" <<'PY'
import json, sys
path, package, release, arch, target, subtarget = sys.argv[1:]
with open(path, 'w', encoding='utf-8') as f:
    json.dump({
        'package_source': package,
        'openwrt_version': release,
        'arch': arch,
        'target': target,
        'subtarget': subtarget,
    }, f, indent=2, sort_keys=True)
    f.write('\n')
PY

printf 'Built %s for OpenWrt %s / %s / %s/%s\n' "$package" "$release" "$arch" "$target" "$subtarget"
