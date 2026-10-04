#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-package-batch.sh --release VERSION --arch ARCH --tasks-json JSON \
  --output DIR [--jobs N] [--cache DIR] [--success-hook SCRIPT]

Build pending AudioWRT package sources for one architecture. Tasks are grouped
by target/subtarget. Each OpenWrt SDK/context is prepared once, all requested
package sources are installed into the feed once, defconfig runs once, and the
packages are then compiled sequentially. An optional success hook runs
immediately after each successful package output is captured.
EOF
}

release=""; arch=""; tasks_json=""; output_root=""; jobs=4; cache=".cache/audiowrt-packages"; success_hook=""
while (($#)); do
  case "$1" in
    --release) release="$2"; shift 2 ;;
    --arch) arch="$2"; shift 2 ;;
    --tasks-json) tasks_json="$2"; shift 2 ;;
    --output) output_root="$2"; shift 2 ;;
    --jobs) jobs="$2"; shift 2 ;;
    --cache) cache="$2"; shift 2 ;;
    --success-hook) success_hook="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
for value in release arch tasks_json output_root; do
  [[ -n "${!value}" ]] || { echo "ERROR: --${value//_/-} is required" >&2; exit 2; }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_build_packages_file="$repo_root/config/build/source-build-packages"

is_source_build_package() {
  local package="$1"
  [[ -f "$source_build_packages_file" ]] || return 1
  grep -Ev '^[[:space:]]*(#|$)' "$source_build_packages_file" | grep -Fxq "$package"
}

if [[ -n "$success_hook" ]]; then
  success_hook="$(cd "$(dirname "$success_hook")" && pwd)/$(basename "$success_hook")"
  [[ -f "$success_hook" ]] || { echo "ERROR: success hook not found: $success_hook" >&2; exit 2; }
fi

mkdir -p "$cache" "$output_root"
cache="$(cd "$cache" && pwd)"
output_root="$(cd "$output_root" && pwd)"
failures_file="$output_root/build-failures.txt"
: > "$failures_file"

mapfile -t contexts < <(TASKS_JSON="$tasks_json" python3 - <<'PY'
import json, os
seen=set()
for t in json.loads(os.environ['TASKS_JSON']):
    k=(t['target'], t['subtarget'])
    if k not in seen:
        seen.add(k)
        print('\t'.join(k))
PY
)

prepare_sdk() {
  local target="$1" subtarget="$2"
  local base_url index archive archive_path feeds_buildinfo sdk_key sdk_parent sdk
  base_url="https://downloads.openwrt.org/releases/$release/targets/$target/$subtarget"
  index="$(curl -fsSL "$base_url/")"
  archive="$(printf '%s' "$index" | grep -oE "openwrt-sdk-${release//./\\.}-${target//-/_}-${subtarget//-/_}[^\"<> ]*Linux-x86_64\\.tar\\.(zst|xz)" | head -n1 || true)"
  [[ -n "$archive" ]] || archive="$(printf '%s' "$index" | grep -oE "openwrt-sdk-${release//./\\.}-[^\"<> ]*Linux-x86_64\\.tar\\.(zst|xz)" | head -n1 || true)"
  [[ -n "$archive" ]] || { echo "ERROR: unable to discover SDK at $base_url/" >&2; return 4; }

  archive_path="$cache/$archive"
  if [[ ! -s "$archive_path" ]]; then
    echo "Downloading $archive" >&2
    curl -fL --retry 3 -o "$archive_path.tmp" "$base_url/$archive" >&2
    mv "$archive_path.tmp" "$archive_path"
  fi

  feeds_buildinfo="$cache/feeds-$release-$target-$subtarget.buildinfo"
  if [[ ! -s "$feeds_buildinfo" ]]; then
    echo "Downloading exact release feed revisions for $release / $target/$subtarget" >&2
    curl -fL --retry 3 -o "$feeds_buildinfo.tmp" "$base_url/feeds.buildinfo" >&2
    mv "$feeds_buildinfo.tmp" "$feeds_buildinfo"
  fi

  sdk_key="v5-exact-$release-$target-$subtarget"
  sdk_parent="$cache/sdk-$sdk_key"
  sdk="$(find "$sdk_parent" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1 || true)"
  if [[ -z "$sdk" ]]; then
    echo "Preparing clean OpenWrt SDK for $release / $target/$subtarget" >&2
    rm -rf "$sdk_parent"
    mkdir -p "$sdk_parent"
    case "$archive" in
      *.tar.zst) tar --zstd -xf "$archive_path" -C "$sdk_parent" ;;
      *.tar.xz) tar -xJf "$archive_path" -C "$sdk_parent" ;;
      *) return 4 ;;
    esac
    sdk="$(find "$sdk_parent" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  else
    echo "Reusing OpenWrt SDK session for $release / $target/$subtarget" >&2
  fi

  # The SDK feed branches move after a release. Reproduce the exact feed commits
  # recorded by OpenWrt for this target instead of mixing a release SDK with the
  # current feed branch heads.
  cp "$feeds_buildinfo" "$sdk/feeds.conf"
  printf '\nsrc-link audiowrt %s\n' "$repo_root" >> "$sdk/feeds.conf"

  local official_marker="$sdk/.audiowrt-official-feeds-v5-exact-ready"
  if [[ ! -f "$official_marker" ]]; then
    (
      cd "$sdk"
      rm -rf feeds/packages feeds/luci feeds/routing feeds/telephony feeds/video
      ./scripts/feeds update -a

      release_series="${release%.*}"
      rust_patch="$repo_root/repository/sdk-patches/$release_series/packages-rust-use-ci-llvm.patch"
      if [[ -f "$rust_patch" && -f feeds/packages/lang/rust/Makefile ]]; then
        echo "Applying SDK patch: $rust_patch" >&2
        if ! patch -d feeds/packages -p1 --forward --batch < "$rust_patch"; then
          echo "ERROR: failed to apply Rust CI LLVM patch; refusing to build a full LLVM toolchain" >&2
          exit 20
        fi
        grep -q -- '--set=llvm.download-ci-llvm=true' feeds/packages/lang/rust/Makefile || {
          echo "ERROR: Rust CI LLVM patch did not enable llvm.download-ci-llvm" >&2
          exit 21
        }
      fi
    ) >&2
    touch "$official_marker"
  fi

  printf '%s\n' "$sdk"
}

for context in "${contexts[@]}"; do
  IFS=$'\t' read -r target subtarget <<<"$context"
  sdk="$(prepare_sdk "$target" "$subtarget")"

  mapfile -t task_rows < <(TASKS_JSON="$tasks_json" TARGET="$target" SUBTARGET="$subtarget" python3 - <<'PY'
import json, os
seen=set()
for t in json.loads(os.environ['TASKS_JSON']):
    if t['target'] != os.environ['TARGET'] or t['subtarget'] != os.environ['SUBTARGET']:
        continue
    key=(t['package'], t['scope'])
    if key in seen:
        continue
    seen.add(key)
    print('\t'.join(key))
PY
  )

  source_commit="$(git -C "$repo_root" rev-parse HEAD)"
  source_marker="$sdk/.audiowrt-source-$source_commit-ready"
  if [[ ! -f "$source_marker" ]]; then
    echo "Refreshing AudioWRT feed for source $source_commit" >&2
    (cd "$sdk"; ./scripts/feeds update audiowrt) >&2
    find "$sdk" -maxdepth 1 -type f -name '.audiowrt-source-*-ready' -delete
    touch "$source_marker"
  fi

  # Do not let package links or generated Kconfig metadata from a previous
  # cached run leak into the current task set.
  rm -rf "$sdk/package/feeds/audiowrt"
  rm -f "$sdk/tmp/.packageinfo" "$sdk/tmp/.config-package.in"

  echo "Registering ${#task_rows[@]} package source(s) for $target/$subtarget"
  for row in "${task_rows[@]}"; do
    IFS=$'\t' read -r package scope <<<"$row"
    if ! (cd "$sdk"; ./scripts/feeds install -f -p audiowrt "$package") >/dev/null 2>&1; then
      echo "$package|$target|$subtarget|feed-install-failed" >> "$failures_file"
      echo "ERROR: feed install failed for $package" >&2
    fi
  done

  echo "Configuring SDK once for $target/$subtarget"
  config_log="$output_root/config-$release-$arch-$target-$subtarget.log"
  if ! (cd "$sdk"; make defconfig >"$config_log" 2>&1); then
    echo "ERROR: make defconfig failed for $target/$subtarget; last 120 log lines:" >&2
    tail -n 120 "$config_log" >&2 || true
    for row in "${task_rows[@]}"; do
      IFS=$'\t' read -r package scope <<<"$row"
      echo "$package|$target|$subtarget|defconfig-failed" >> "$failures_file"
    done
    continue
  fi

  for row in "${task_rows[@]}"; do
    IFS=$'\t' read -r package scope <<<"$row"
    echo "::group::Task $package / $release / $arch / $target/$subtarget"

    if [[ ! -e "$sdk/package/feeds/audiowrt/$package" ]]; then
      echo "$package|$target|$subtarget|not-registered" >> "$failures_file"
      echo "ERROR: package is not registered in the SDK: $package" >&2
      echo "::endgroup::"
      continue
    fi

    source_dir=""
    for category in audiowrt ported trimmed tailored; do
      candidate="$repo_root/$category/$package"
      [[ -f "$candidate/Makefile" ]] && { source_dir="$candidate"; break; }
    done
    if [[ -z "$source_dir" ]]; then
      echo "$package|$target|$subtarget|unknown-source" >> "$failures_file"
      echo "ERROR: source directory not found for $package" >&2
      echo "::endgroup::"
      continue
    fi

    package_output="$output_root/$package/$release/$arch/$target/$subtarget"
    mkdir -p "$package_output/packages"
    rm -f "$package_output/packages"/*.apk
    build_log="$package_output/build.log"

    make_args=("package/feeds/audiowrt/$package/compile" "-j$jobs")
    if is_source_build_package "$package"; then
      echo "Build $package (source-build dependencies enabled)"
    else
      make_args+=("NO_DEPS=1")
      echo "Build $package (NO_DEPS=1)"
    fi

    if ! (cd "$sdk"; make "${make_args[@]}" >"$build_log" 2>&1); then
      echo "$package|$target|$subtarget|compile-failed" >> "$failures_file"
      echo "ERROR: compile failed for $package; last 120 log lines:" >&2
      tail -n 120 "$build_log" >&2 || true
      echo "::endgroup::"
      continue
    fi

    mapfile -t output_names < <(python3 - "$source_dir/Makefile" <<'PY'
import re, sys
text=open(sys.argv[1], encoding='utf-8').read()
for n in re.findall(r'^define Package/([^\s]+)', text, re.M): print(n)
for n in re.findall(r'^define KernelPackage/([^\s]+)', text, re.M): print('kmod-'+n)
PY
    )

    found=0
    for name in "${output_names[@]}"; do
      while IFS= read -r apk; do
        cp -f "$apk" "$package_output/packages/"
        found=1
      done < <(find "$sdk/bin" -type f -name "$name-*.apk" -print)
    done
    if [[ "$found" != 1 ]]; then
      echo "$package|$target|$subtarget|no-apk" >> "$failures_file"
      echo "ERROR: $package compiled but produced no APK; last 80 log lines:" >&2
      tail -n 80 "$build_log" >&2 || true
      echo "::endgroup::"
      continue
    fi

    python3 - "$package_output/context.json" "$package" "$release" "$arch" "$target" "$subtarget" <<'PY'
import json, sys
path, package, release, arch, target, subtarget=sys.argv[1:]
with open(path,'w',encoding='utf-8') as f:
    json.dump({'package_source':package,'openwrt_version':release,'arch':arch,'target':target,'subtarget':subtarget},f,indent=2,sort_keys=True)
    f.write('\n')
PY
    echo "Built $package"

    if [[ -n "$success_hook" ]]; then
      if ! PACKAGE_NAME="$package" PACKAGE_SCOPE="$scope" PACKAGE_OUTPUT="$package_output" \
          RELEASE="$release" ARCH="$arch" TARGET="$target" SUBTARGET="$subtarget" \
          SOURCE_COMMIT="$source_commit" bash "$success_hook"; then
        echo "$package|$target|$subtarget|success-hook-failed" >> "$failures_file"
        echo "ERROR: success hook failed for $package" >&2
        echo "::endgroup::"
        continue
      fi
    fi

    echo "::endgroup::"
  done
done

if [[ -s "$failures_file" ]]; then
  echo "Some package tasks failed; successful outputs were already preserved/published:" >&2
  cat "$failures_file" >&2
  exit 1
fi
