#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-package-context.sh --package NAME --release VERSION --arch ARCH \
  --target TARGET --subtarget SUBTARGET --output DIR [--jobs N] [--cache DIR]

Builds exactly one AudioWRT package source in one OpenWrt build context.
The AudioWRT repository itself is used as an OpenWrt feed; demonccc/audiowrt is
not consulted or cloned.
EOF
}

package=""
release=""
arch=""
target=""
subtarget=""
output=""
jobs=4
cache=".cache/audiowrt-packages"

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

mkdir -p "$cache" "$output/packages"
cache="$(cd "$cache" && pwd)"
output="$(cd "$output" && pwd)"

base_url="https://downloads.openwrt.org/releases/$release/targets/$target/$subtarget"
index="$(curl -fsSL "$base_url/")"
archive="$(printf '%s' "$index" | grep -oE "openwrt-sdk-${release//./\.}-${target//-/_}-${subtarget//-/_}[^\"<> ]*Linux-x86_64\.tar\.(zst|xz)" | head -n1 || true)"
if [[ -z "$archive" ]]; then
  # OpenWrt target naming can retain dashes. Fall back to a release/target prefix match.
  archive="$(printf '%s' "$index" | grep -oE "openwrt-sdk-${release//./\.}-[^\"<> ]*Linux-x86_64\.tar\.(zst|xz)" | head -n1 || true)"
fi
[[ -n "$archive" ]] || { echo "ERROR: unable to discover SDK at $base_url/" >&2; exit 4; }

archive_path="$cache/$archive"
if [[ ! -s "$archive_path" ]]; then
  echo "Downloading $archive"
  curl -fL --retry 3 -o "$archive_path.tmp" "$base_url/$archive"
  mv "$archive_path.tmp" "$archive_path"
fi

sdk_key="$release-$target-$subtarget"
sdk_parent="$cache/sdk-$sdk_key"
rm -rf "$sdk_parent"
mkdir -p "$sdk_parent"
case "$archive" in
  *.tar.zst) tar --zstd -xf "$archive_path" -C "$sdk_parent" ;;
  *.tar.xz) tar -xJf "$archive_path" -C "$sdk_parent" ;;
  *) echo "ERROR: unsupported SDK archive: $archive" >&2; exit 4 ;;
esac
sdk="$(find "$sdk_parent" -mindepth 1 -maxdepth 1 -type d | head -n1)"
[[ -n "$sdk" ]] || { echo "ERROR: SDK extraction produced no directory" >&2; exit 4; }

# Use this repository directly as an OpenWrt feed. Official package/luci feeds
# remain SDK-pinned by OpenWrt's feeds.conf.default.
cp "$sdk/feeds.conf.default" "$sdk/feeds.conf"
printf '\nsrc-link audiowrt %s\n' "$repo_root" >> "$sdk/feeds.conf"

(
  cd "$sdk"
  ./scripts/feeds update -a
  ./scripts/feeds install -a
  make defconfig

  target_path="package/feeds/audiowrt/$package/compile"
  [[ -e "package/feeds/audiowrt/$package" ]] || {
    echo "ERROR: AudioWRT feed did not register source package $package" >&2
    exit 5
  }
  make "$target_path" -j"$jobs" V=s
)

# Collect only APK outputs declared by this AudioWRT source Makefile. Dependency
# APKs built as part of SDK preparation are not published as AudioWRT artifacts.
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
