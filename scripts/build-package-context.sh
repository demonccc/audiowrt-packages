#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-package-context.sh --package NAME --release VERSION --arch ARCH \
  --target TARGET --subtarget SUBTARGET --output DIR [--jobs N] [--cache DIR]

Build one AudioWRT package root in a clean OpenWrt SDK context. The build uses
OpenWrt's normal dependency traversal, matching the package-build behavior used
for AudioWRT snapshot builds. Firmware profiles, devices and flavors do not
participate.
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
build_targets="$repo_root/config/build/package-build-targets"
resolver="$repo_root/scripts/resolve-package-build-targets.py"

for required in "$build_targets" "$resolver"; do
  [[ -f "$required" ]] || { echo "ERROR: required build input is missing: $required" >&2; exit 3; }
done

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

(
  cd "$sdk"

  # Snapshot-style dependency environment: make the complete official OpenWrt
  # package universe visible to Kconfig and let OpenWrt traverse/stage the real
  # dependencies while compiling. AudioWRT itself is NOT installed as a feed;
  # its sources are linked explicitly below, which avoids the self-cycles caused
  # by installing every AudioWRT package through feeds install -a.
  ./scripts/feeds update -a
  ./scripts/feeds install -a

  rm -rf package/feeds/audiowrt
  mkdir -p package/feeds/audiowrt
  while IFS='|' read -r owned target_path extra; do
    [[ -n "$owned" && "$owned" != \#* ]] || continue
    [[ -z "${extra:-}" ]] || { echo "ERROR: invalid package-build-targets entry: $owned" >&2; exit 5; }
    [[ "$target_path" == package/feeds/audiowrt/*/compile ]] || continue

    source_path=""
    for category in audiowrt ported trimmed tailored; do
      while IFS= read -r makefile; do
        if grep -Eq "^define (Package/${owned}|KernelPackage/${owned#kmod-})([[:space:]]|$)" "$makefile"; then
          source_path="$(dirname "$makefile")"
          break 2
        fi
      done < <(find "$repo_root/$category" -mindepth 2 -maxdepth 2 -name Makefile -type f | sort)
    done
    [[ -n "$source_path" ]] || { echo "ERROR: source directory not found for $owned" >&2; exit 5; }

    source_rel="${target_path#package/feeds/audiowrt/}"
    source_rel="${source_rel%/compile}"
    destination="package/feeds/audiowrt/$source_rel"
    mkdir -p "$(dirname "$destination")"
    [[ -e "$destination" || -L "$destination" ]] || ln -s "$source_path" "$destination"
  done < "$build_targets"

  make VERSION_NUMBER="$release" -s prepare-tmpinfo
  make VERSION_NUMBER="$release" defconfig
  packageinfo="$sdk/tmp/.packageinfo"
  [[ -s "$packageinfo" ]] || { echo "ERROR: OpenWrt package metadata was not generated" >&2; exit 5; }

  build_plan="$sdk/tmp/audiowrt-build-plan.txt"
  python3 "$resolver" "$build_targets" "$packageinfo" "$package" > "$build_plan"
  mapfile -t build_specs < "$build_plan"
  ((${#build_specs[@]})) || { echo "ERROR: no AudioWRT build targets resolved for $package" >&2; exit 5; }

  build_packages=()
  ordered_targets=()
  declare -A ordered_target_seen=()
  for spec in "${build_specs[@]}"; do
    build_package="${spec%%|*}"
    target_path="${spec#*|}"
    [[ -n "$build_package" && -n "$target_path" && "$target_path" != "$spec" ]] || {
      echo "ERROR: invalid build plan entry: $spec" >&2
      exit 5
    }
    build_packages+=("$build_package")
    if [[ -z "${ordered_target_seen[$target_path]+x}" ]]; then
      ordered_targets+=("$target_path")
      ordered_target_seen["$target_path"]=1
    fi
  done

  for name in "${build_packages[@]}"; do
    sed -i -E "/^(# )?CONFIG_PACKAGE_${name}(=| is not set)/d" .config 2>/dev/null || true
    printf 'CONFIG_PACKAGE_%s=m\n' "$name" >> .config
  done
  make VERSION_NUMBER="$release" defconfig

  echo "AudioWRT dependency closure for $package:"
  printf '  %s\n' "${build_specs[@]}"

  # Compile in the AudioWRT topological order, but deliberately do not use
  # NO_DEPS. OpenWrt compiles/stages official dependencies exactly as it does
  # in snapshot package builds. Only AudioWRT root outputs are exported later.
  for target_path in "${ordered_targets[@]}"; do
    target_roots=()
    for spec in "${build_specs[@]}"; do
      [[ "${spec#*|}" == "$target_path" ]] || continue
      target_roots+=("${spec%%|*}")
    done

    target_plan="$sdk/tmp/audiowrt-target-plan.txt"
    python3 "$resolver" "$build_targets" "$sdk/tmp/.packageinfo" "${target_roots[@]}" \
      --providers "${build_packages[@]}" > "$target_plan"
    mapfile -t target_specs < "$target_plan"
    declare -A target_package_seen=()
    for spec in "${target_specs[@]}"; do
      target_package_seen["${spec%%|*}"]=1
    done

    target_config_args=()
    for name in "${build_packages[@]}"; do
      if [[ -n "${target_package_seen[$name]+x}" ]]; then
        target_config_args+=("CONFIG_PACKAGE_${name}=m")
      else
        target_config_args+=("CONFIG_PACKAGE_${name}=n")
      fi
    done

    if [[ "$target_path" != *"/kmod-bluetooth-trimmed/compile" ]]; then
      target_config_args+=("CONFIG_PACKAGE_kmod-bluetooth=n")
    fi

    echo "Building AudioWRT target with OpenWrt dependency traversal: $target_path"
    make VERSION_NUMBER="$release" "${target_config_args[@]}" "$target_path" -j"$jobs" V=s
  done
)

# Export only the requested root outputs. Official dependencies and transitive
# AudioWRT providers are internal build inputs and are not published by this task.
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
