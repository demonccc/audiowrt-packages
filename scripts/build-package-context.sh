#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-package-context.sh --package NAME [--package NAME ...] \
  --release VERSION --arch ARCH --target TARGET --subtarget SUBTARGET \
  --output DIR [--jobs N] [--cache DIR]

Build all requested AudioWRT roots for one release + architecture +
target/subtarget in a single clean OpenWrt SDK context. This matches the stateful
package build model used by AudioWRT snapshot profiles while remaining
profile/device/flavor agnostic.
EOF
}

packages=()
release=""
arch=""
target=""
subtarget=""
output=""
jobs=4
cache="${RUNNER_TEMP:-/tmp}/audiowrt-packages-cache"

while (($#)); do
  case "$1" in
    --package) packages+=("$2"); shift 2 ;;
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

(("${#packages[@]}")) || { echo "ERROR: at least one --package is required" >&2; exit 2; }
for value in release arch target subtarget output; do
  [[ -n "${!value}" ]] || { echo "ERROR: --${value//_/-} is required" >&2; exit 2; }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_targets="$repo_root/config/build/package-build-targets"
source_build_packages="$repo_root/config/build/source-build-packages"
resolver="$repo_root/scripts/resolve-package-build-targets.py"
source_dep_resolver="$repo_root/scripts/resolve-source-build-dependencies.py"
runtime_dep_resolver="$repo_root/scripts/resolve-runtime-library-dependencies.py"
source_paths="$repo_root/config/build/openwrt-source-paths"
materialize_feed_source="$repo_root/scripts/materialize-openwrt-feed-source.py"

for required in "$build_targets" "$source_build_packages" "$resolver" "$source_dep_resolver" "$runtime_dep_resolver" "$source_paths" "$materialize_feed_source" "$repo_root/scripts/snapshot-sdk-staging.sh"; do
  [[ -f "$required" ]] || { echo "ERROR: required build input is missing: $required" >&2; exit 3; }
done

declare -A root_source_dir=()
for root_package in "${packages[@]}"; do
  source_dir=""
  for category in audiowrt ported trimmed tailored; do
    while IFS= read -r makefile; do
      if grep -Eq "^define (Package/${root_package}|KernelPackage/${root_package#kmod-})([[:space:]]|$)" "$makefile"; then
        source_dir="$(dirname "$makefile")"
        break 2
      fi
    done < <(find "$repo_root/$category" -mindepth 2 -maxdepth 2 -name Makefile -type f | sort)
  done
  [[ -n "$source_dir" ]] || { echo "ERROR: unknown AudioWRT package source: $root_package" >&2; exit 3; }
  root_source_dir["$root_package"]="$source_dir"
done

mkdir -p "$cache" "$output"
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

(
  cd "$sdk"

  sdk_dir="$sdk"
  work_dir="$sdk/tmp/audiowrt-work"
  arch_packages="$arch"
  mkdir -p "$work_dir"

  json_field() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))[sys.argv[2]])' "$1" "$2"
  }

  download_file() {
    local url="$1" destination="$2"
    mkdir -p "$(dirname "$destination")"
    echo "Downloading: $url"
    curl -fL --retry 3 -o "$destination" "$url"
  }

  make_run() {
    local cwd="$1"; shift
    echo "+ (cd $cwd && make $*)"
    make -C "$cwd" "$@"
  }

  artifacts_metadata="$work_dir/openwrt-artifacts.json"
  python3 "$repo_root/scripts/resolve-openwrt-artifacts.py" "$release" "$target" "$subtarget" > "$artifacts_metadata"
  openwrt_base_url="$(json_field "$artifacts_metadata" base_url)"
  kmod_bluetooth_url="$(json_field "$artifacts_metadata" kmod_bluetooth_url)"
  kmod_btmtk_url="$(json_field "$artifacts_metadata" kmod_btmtk_url)"
  kmod_btusb_url="$(json_field "$artifacts_metadata" kmod_btusb_url)"
  kmods_sha256sums_url="$(json_field "$artifacts_metadata" kmods_sha256sums_url)"

  export AUDIOWRT_BLUETOOTH_SOURCE_DIR="$repo_root/tailored/kmod-bluetooth-tailored"
  export AUDIOWRT_BLUETOOTH_CACHE_DIR="$cache/bluetooth-modules/$release/$target/$subtarget"
  source "$repo_root/scripts/snapshot-sdk-staging.sh"

  # The package repository is the only enabled feed. OpenWrt packages/LuCI
  # sources used as canonical recipe/header inputs are sparse materialized from
  # the exact refs pinned by the SDK, but are never indexed as feeds.
  upstream_cache="$cache/openwrt-source/$release"
  python3 "$materialize_feed_source" "$sdk" packages "$upstream_cache" "$source_paths"
  python3 "$materialize_feed_source" "$sdk" luci "$upstream_cache" "$source_paths"

  cat > feeds.conf <<EOF
src-link audiowrt $repo_root
EOF
  echo "Enabled feeds:"
  cat feeds.conf
  ./scripts/feeds update audiowrt

  rm -rf package/feeds/audiowrt
  mkdir -p package/feeds/audiowrt
  owned_packages=()
  while IFS='|' read -r owned target_path extra; do
    [[ -n "$owned" && "$owned" != \#* ]] || continue
    [[ -z "${extra:-}" ]] || { echo "ERROR: invalid package-build-targets entry: $owned" >&2; exit 5; }
    owned_packages+=("$owned")
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

  # Select every requested root before resolving the shared AudioWRT-owned
  # closure. All roots in this target/subtarget share one SDK state.
  for root_package in "${packages[@]}"; do
    sed -i -E "/^(# )?CONFIG_PACKAGE_${root_package}(=| is not set)/d" .config 2>/dev/null || true
    printf 'CONFIG_PACKAGE_%s=m\n' "$root_package" >> .config
  done
  make VERSION_NUMBER="$release" defconfig

  packageinfo="$sdk/tmp/.packageinfo"
  [[ -s "$packageinfo" ]] || { echo "ERROR: OpenWrt package metadata was not generated" >&2; exit 5; }

  # All AudioWRT-owned providers are candidates. The resolver only selects one
  # when the root actually depends on the capability (alsa-lib, wpa-supplicant,
  # Bluetooth kmods, etc.).
  build_plan="$work_dir/audiowrt-build-plan.txt"
  python3 "$resolver" "$build_targets" "$packageinfo" "${packages[@]}" \
    --providers "${owned_packages[@]}" > "$build_plan"
  mapfile -t build_specs < "$build_plan"
  (("${#build_specs[@]}")) || { echo "ERROR: no AudioWRT build targets resolved for requested roots" >&2; exit 5; }

  declare -A source_build_package=()
  while IFS= read -r name; do
    [[ -n "$name" && "$name" != \#* ]] || continue
    source_build_package["$name"]=1
  done < "$source_build_packages"

  build_packages=()
  package_only_packages=()
  source_packages=()
  ordered_targets=()
  declare -A source_target_seen=()
  declare -A ordered_target_seen=()

  for spec in "${build_specs[@]}"; do
    build_package="${spec%%|*}"
    target_path="${spec#*|}"
    build_packages+=("$build_package")
    if [[ -n "${source_build_package[$build_package]+x}" ]]; then
      source_packages+=("$build_package")
      source_target_seen["$target_path"]=1
    else
      package_only_packages+=("$build_package")
    fi
    if [[ -z "${ordered_target_seen[$target_path]+x}" ]]; then
      ordered_targets+=("$target_path")
      ordered_target_seen["$target_path"]=1
    fi
  done

  firmware_packages=("${build_packages[@]}")

  # Keep every selected AudioWRT provider enabled while official build-only
  # dependencies are prepared. This is what prevents official GLib/ALSA/etc.
  # from becoming the runtime provider.
  for name in "${build_packages[@]}"; do
    sed -i -E "/^(# )?CONFIG_PACKAGE_${name}(=| is not set)/d" .config 2>/dev/null || true
    printf 'CONFIG_PACKAGE_%s=m\n' "$name" >> .config
  done
  make VERSION_NUMBER="$release" defconfig
  packageinfo="$sdk/tmp/.packageinfo"

  native_player_sdk=0
  hostap_sdk=0
  if [[ " ${build_packages[*]} " == *" libaudiowrt-player "* ||
        " ${build_packages[*]} " == *" audiowrt-player-flac "* ||
        " ${build_packages[*]} " == *" audiowrt-player-mp3 "* ||
        " ${build_packages[*]} " == *" audiowrt-player-aac "* ||
        " ${build_packages[*]} " == *" audiowrt-player-wav "* ||
        " ${build_packages[*]} " == *" audiowrt-player-vorbis "* ||
        " ${build_packages[*]} " == *" audiowrt-player-opus "* ]]; then
    native_player_sdk=1
  fi
  [[ " ${build_packages[*]} " == *" hostapd-wpa-supplicant-tailored "* ]] && hostap_sdk=1

  if (( native_player_sdk )); then
    register_official_sdk_source base libs/libubox
    register_official_sdk_source base libs/uclient
    register_official_sdk_source base libs/ustream-ssl
    [[ " ${build_packages[*]} " == *" audiowrt-player-flac "* ]] && register_official_sdk_source packages libs/flac
    [[ " ${build_packages[*]} " == *" audiowrt-player-mp3 "* ]] && register_official_sdk_source packages libs/libmad
    [[ " ${build_packages[*]} " == *" audiowrt-player-aac "* ]] && register_official_sdk_source packages libs/faad2
    if [[ " ${build_packages[*]} " == *" audiowrt-player-vorbis "* ||
          " ${build_packages[*]} " == *" audiowrt-player-opus "* ]]; then
      register_official_sdk_source packages libs/libogg
    fi
    if [[ " ${build_packages[*]} " == *" audiowrt-player-vorbis "* ]]; then
      register_official_sdk_source packages libs/libvorbis
    fi
    if [[ " ${build_packages[*]} " == *" audiowrt-player-opus "* ]]; then
      register_official_sdk_source packages libs/opus
      register_official_sdk_source packages libs/opusfile
    fi
  fi

  if (( hostap_sdk )); then
    register_official_sdk_source base libs/libnl-tiny
    register_official_sdk_source base libs/libjson-c
    register_official_sdk_source base libs/mbedtls
    register_official_sdk_source base libs/libubox
    register_official_sdk_source base system/ubus
    register_official_sdk_source base utils/ucode
    register_official_sdk_source base libs/udebug
  fi

  if [[ " ${build_packages[*]} " == *" kmod-bluetooth-tailored "* ]]; then
    prepare_bluetooth_package
  fi

  # Only explicit build/host dependencies of genuine source packages are
  # prepared. Runtime dependencies are never turned into source-build roots.
  # No OpenWrt feed is updated/installed here and every helper target runs with
  # NO_DEPS=1 so it cannot recursively rebuild OpenWrt packages or kernel kmods.
  source_dependencies=()
  source_dependency_targets=()
  if (("${#source_packages[@]}")); then
    source_dependencies_file="$work_dir/source-build-dependencies.txt"
    python3 "$source_dep_resolver" "$build_targets" "$packageinfo" \
      "${source_packages[@]}" --providers "${build_packages[@]}" > "$source_dependencies_file"
    mapfile -t source_dependencies < "$source_dependencies_file"

    for dependency_spec in "${source_dependencies[@]}"; do
      dependency_name="${dependency_spec%%/*}"
      dependency_variant=""
      [[ "$dependency_spec" == */* ]] && dependency_variant="${dependency_spec#*/}"

      case "$dependency_name" in
        glib2)
          register_official_sdk_source packages libs/glib2
          dependency_dir="package/feeds/packages/glib2"
          ;;
        rust)
          register_official_sdk_source packages lang/rust
          dependency_dir="package/feeds/packages/rust"
          ;;
        openssl)
          dependency_dir="package/libs/openssl"
          ;;
        *)
          echo "ERROR: unsupported explicit source-build dependency without a staging rule: $dependency_spec" >&2
          exit 5
          ;;
      esac

      dependency_target="$dependency_dir/compile"
      if [[ "$dependency_variant" == "host" ]]; then
        dependency_target="$dependency_dir/host/compile"
      fi
      source_dependency_targets+=("$dependency_target")
    done

    if (("${#source_dependency_targets[@]}")); then
      make VERSION_NUMBER="$release" -s prepare-tmpinfo
      make VERSION_NUMBER="$release" defconfig
      echo "Preparing explicit build-only dependencies (NO_DEPS=1; no feed traversal):"
      printf '  %s\n' "${source_dependency_targets[@]}"
      make VERSION_NUMBER="$release" "${source_dependency_targets[@]}" NO_DEPS=1 -j"$jobs" V=s
    fi
  fi

  package_config_args=()
  for name in "${build_packages[@]}"; do
    package_config_args+=("CONFIG_PACKAGE_${name}=m")
  done

  make VERSION_NUMBER="$release" package/toolchain/compile NO_DEPS=1 -j"$jobs"

  # Package-only AudioWRT recipes still run OpenWrt's CheckDependencies. Stage
  # SONAME provider metadata from the exact official runtime APKs instead of
  # rebuilding those dependencies from source. Selected AudioWRT providers are
  # filtered by the resolver, so official packages never replace trimmed/custom
  # runtime providers.
  target_staging="$(find "$sdk/staging_dir" -mindepth 1 -maxdepth 1 -type d -name 'target-*' | head -n1)"
  [[ -n "$target_staging" ]] || { echo "ERROR: target staging directory not found" >&2; exit 5; }
  runtime_dependencies_file="$work_dir/runtime-library-dependencies.txt"
  python3 "$runtime_dep_resolver" "$build_targets" "$packageinfo" \
    "${build_packages[@]}" --providers "${build_packages[@]}" > "$runtime_dependencies_file"
  mapfile -t runtime_dependencies < "$runtime_dependencies_file"
  for runtime_dependency in "${runtime_dependencies[@]}"; do
    stage_official_runtime_provides "$runtime_dependency" "$target_staging"
  done

  if (( native_player_sdk )); then
    prepare_native_player_sdk
  fi
  if (( hostap_sdk )); then
    prepare_hostap_sdk
  fi

  echo "AudioWRT shared dependency closure for: ${packages[*]}"
  printf '  %s\n' "${build_specs[@]}"

  download_targets=()
  for target_path in "${ordered_targets[@]}"; do
    download_targets+=("${target_path%/compile}/download")
  done
  if (("${#download_targets[@]}")); then
    make VERSION_NUMBER="$release" "${package_config_args[@]}" "${download_targets[@]}" NO_DEPS=1 -j"$jobs"
  fi

  # Compile in the same topological/source-vs-package-only order as AudioWRT.
  # Official source dependencies are prepared before this loop, so they cannot
  # overwrite a trimmed AudioWRT runtime provider after it has been staged.
  for target_path in "${ordered_targets[@]}"; do
    target_roots=()
    for spec in "${build_specs[@]}"; do
      [[ "${spec#*|}" == "$target_path" ]] || continue
      target_roots+=("${spec%%|*}")
    done

    target_plan="$work_dir/audiowrt-target-plan.txt"
    python3 "$resolver" "$build_targets" "$packageinfo" "${target_roots[@]}" \
      --providers "${build_packages[@]}" > "$target_plan"
    mapfile -t target_specs < "$target_plan"
    declare -A target_package_seen=()
    for spec in "${target_specs[@]}"; do
      target_package_seen["${spec%%|*}"]=1
    done

    # Keep the entire resolved AudioWRT closure selected for every target. The
    # SDK is shared, so providers built earlier (for example glib2-trimmed and
    # sbc-trimmed) must remain selected/staged for later consumers.
    target_config_args=("${package_config_args[@]}")
    if [[ -n "${source_target_seen[$target_path]+x}" ]]; then
      target_config_args+=("CONFIG_PACKAGE_kmod-bluetooth=n")
      target_config_args+=("CONFIG_PACKAGE_kmod-bluetooth-tailored=n")
    fi

    # All official development dependencies were compiled above. AudioWRT
    # targets therefore compile with NO_DEPS=1, including genuine source-build
    # packages, so OpenWrt cannot rebuild an official dependency after a custom
    # runtime provider has been staged and overwrite its provider metadata.
    printf '\n[BUILD] %s -> %s\n' "${target_roots[*]}" "$target_path"
    if ! make VERSION_NUMBER="$release" "${target_config_args[@]}" "$target_path" NO_DEPS=1 -j"$jobs" V=s; then
      printf '[FAIL] %s -> %s\n' "${target_roots[*]}" "$target_path" >&2
      continue
    fi
    printf '[ OK ] %s -> %s\n' "${target_roots[*]}" "$target_path"
  done
)

# Export each requested root independently from the one shared SDK. Missing roots
# are recorded instead of discarding APKs successfully produced for other roots.
: > "$output/build-failures.txt"
for root_package in "${packages[@]}"; do
  root_output="$output/$root_package"
  rm -rf "$root_output"
  mkdir -p "$root_output/packages"

  mapfile -t output_names < <(python3 - "${root_source_dir[$root_package]}/Makefile" <<'PY'
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
      cp -f "$apk" "$root_output/packages/"
      found=1
    done < <(find "$sdk/bin" -type f -name "$name-*.apk" -print)
  done

  if [[ "$found" != 1 ]]; then
    printf '%s|compile-failed\n' "$root_package" >> "$output/build-failures.txt"
    continue
  fi

  python3 - "$root_output/context.json" "$root_package" "$release" "$arch" "$target" "$subtarget" <<'PY'
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
done

printf 'Shared SDK build complete for OpenWrt %s / %s / %s/%s (%s)\n' \
  "$release" "$arch" "$target" "$subtarget" "${packages[*]}"
