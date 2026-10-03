#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-package-batch.sh --release VERSION --arch ARCH --tasks-json JSON \
  --output DIR [--jobs N] [--cache DIR]

Build all pending AudioWRT package sources for one architecture. Tasks are grouped
by target/subtarget. Each OpenWrt SDK is prepared once and all package targets for
that build context are passed to one make invocation so OpenWrt resolves and
builds shared dependencies only once.
EOF
}

release=""
arch=""
tasks_json=""
output_root=""
jobs=4
cache=".cache/audiowrt-packages"

while (($#)); do
  case "$1" in
    --release) release="$2"; shift 2 ;;
    --arch) arch="$2"; shift 2 ;;
    --tasks-json) tasks_json="$2"; shift 2 ;;
    --output) output_root="$2"; shift 2 ;;
    --jobs) jobs="$2"; shift 2 ;;
    --cache) cache="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for value in release arch tasks_json output_root; do
  [[ -n "${!value}" ]] || { echo "ERROR: --${value//_/-} is required" >&2; exit 2; }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$cache" "$output_root"
cache="$(cd "$cache" && pwd)"
output_root="$(cd "$output_root" && pwd)"

mapfile -t contexts < <(TASKS_JSON="$tasks_json" python3 - <<'PY'
import json, os
seen = set()
for task in json.loads(os.environ['TASKS_JSON']):
    key = (task['target'], task['subtarget'])
    if key not in seen:
        seen.add(key)
        print('\t'.join(key))
PY
)

prepare_sdk() {
  local target="$1" subtarget="$2"
  local base_url index archive archive_path sdk_key sdk_parent sdk

  base_url="https://downloads.openwrt.org/releases/$release/targets/$target/$subtarget"
  index="$(curl -fsSL "$base_url/")"
  archive="$(printf '%s' "$index" | grep -oE "openwrt-sdk-${release//./\\.}-${target//-/_}-${subtarget//-/_}[^\"<> ]*Linux-x86_64\\.tar\\.(zst|xz)" | head -n1 || true)"
  if [[ -z "$archive" ]]; then
    archive="$(printf '%s' "$index" | grep -oE "openwrt-sdk-${release//./\\.}-[^\"<> ]*Linux-x86_64\\.tar\\.(zst|xz)" | head -n1 || true)"
  fi
  [[ -n "$archive" ]] || { echo "ERROR: unable to discover SDK at $base_url/" >&2; return 4; }

  archive_path="$cache/$archive"
  if [[ ! -s "$archive_path" ]]; then
    echo "Downloading $archive"
    curl -fL --retry 3 -o "$archive_path.tmp" "$base_url/$archive"
    mv "$archive_path.tmp" "$archive_path"
  fi

  sdk_key="$release-$target-$subtarget"
  sdk_parent="$cache/sdk-$sdk_key"
  sdk="$(find "$sdk_parent" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1 || true)"
  if [[ -z "$sdk" ]]; then
    echo "Preparing OpenWrt SDK for $release / $target/$subtarget"
    rm -rf "$sdk_parent"
    mkdir -p "$sdk_parent"
    case "$archive" in
      *.tar.zst) tar --zstd -xf "$archive_path" -C "$sdk_parent" ;;
      *.tar.xz) tar -xJf "$archive_path" -C "$sdk_parent" ;;
      *) echo "ERROR: unsupported SDK archive: $archive" >&2; return 4 ;;
    esac
    sdk="$(find "$sdk_parent" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    [[ -n "$sdk" ]] || { echo "ERROR: SDK extraction produced no directory" >&2; return 4; }
  else
    echo "Reusing prepared OpenWrt SDK for $release / $target/$subtarget"
  fi

  local official_marker="$sdk/.audiowrt-official-feeds-ready"
  cp "$sdk/feeds.conf.default" "$sdk/feeds.conf"
  printf '\nsrc-link audiowrt %s\n' "$repo_root" >> "$sdk/feeds.conf"
  if [[ ! -f "$official_marker" ]]; then
    (
      cd "$sdk"
      ./scripts/feeds update -a
      ./scripts/feeds install -a
    )
    touch "$official_marker"
  fi

  local source_commit source_marker
  source_commit="$(git -C "$repo_root" rev-parse HEAD)"
  source_marker="$sdk/.audiowrt-source-$source_commit-ready"
  if [[ ! -f "$source_marker" ]]; then
    echo "Refreshing AudioWRT feed for source $source_commit"
    (
      cd "$sdk"
      ./scripts/feeds update audiowrt
      ./scripts/feeds install -a -p audiowrt
      make defconfig
    )
    find "$sdk" -maxdepth 1 -type f -name '.audiowrt-source-*-ready' -delete
    touch "$source_marker"
  fi

  printf '%s\n' "$sdk"
}

for context in "${contexts[@]}"; do
  IFS=$'\t' read -r target subtarget <<<"$context"
  echo "::group::Prepare context $release / $arch / $target/$subtarget"
  sdk="$(prepare_sdk "$target" "$subtarget" | tee /dev/stderr | tail -n1)"
  echo "::endgroup::"

  mapfile -t packages < <(TASKS_JSON="$tasks_json" TARGET="$target" SUBTARGET="$subtarget" python3 - <<'PY'
import json, os
seen = set()
for task in json.loads(os.environ['TASKS_JSON']):
    if task['target'] == os.environ['TARGET'] and task['subtarget'] == os.environ['SUBTARGET']:
        p = task['package']
        if p not in seen:
            seen.add(p)
            print(p)
PY
  )

  targets=()
  for package in "${packages[@]}"; do
    [[ -e "$sdk/package/feeds/audiowrt/$package" ]] || {
      echo "ERROR: AudioWRT feed did not register source package $package" >&2
      exit 5
    }
    targets+=("package/feeds/audiowrt/$package/compile")
  done

  echo "::group::Build ${#packages[@]} package source(s) / $release / $arch / $target/$subtarget"
  (
    cd "$sdk"
    make "${targets[@]}" -j"$jobs" V=s
  )
  echo "::endgroup::"

  for package in "${packages[@]}"; do
    source_dir=""
    for category in audiowrt ported trimmed tailored; do
      candidate="$repo_root/$category/$package"
      if [[ -f "$candidate/Makefile" ]]; then
        source_dir="$candidate"
        break
      fi
    done
    [[ -n "$source_dir" ]] || { echo "ERROR: unknown AudioWRT package source: $package" >&2; exit 3; }

    package_output="$output_root/$package/$release/$arch/$target/$subtarget"
    mkdir -p "$package_output/packages"

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
        cp -f "$apk" "$package_output/packages/"
        found=1
      done < <(find "$sdk/bin" -type f -name "$name-*.apk" -print)
    done
    [[ "$found" == 1 ]] || { echo "ERROR: no APK output found for $package" >&2; exit 6; }

    python3 - "$package_output/context.json" "$package" "$release" "$arch" "$target" "$subtarget" <<'PY'
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
    echo "Built $package for OpenWrt $release / $arch / $target/$subtarget"
  done
done
