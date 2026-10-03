#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-package-batch.sh --release VERSION --arch ARCH --tasks-json JSON \
  --output DIR [--jobs N] [--cache DIR]

Build all pending AudioWRT package sources for one architecture. Tasks are grouped
by target/subtarget. Each OpenWrt SDK is prepared once and all requested package
targets for that context are built in one make invocation.
EOF
}

release=""; arch=""; tasks_json=""; output_root=""; jobs=4; cache=".cache/audiowrt-packages"
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
  local base_url index archive archive_path sdk_key sdk_parent sdk
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

  # v3 deliberately invalidates SDKs polluted by the old `feeds install -a`
  # behavior. The archive itself remains cached.
  sdk_key="v3-$release-$target-$subtarget"
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
    echo "Reusing clean OpenWrt SDK for $release / $target/$subtarget" >&2
  fi

  cp "$sdk/feeds.conf.default" "$sdk/feeds.conf"
  printf '\nsrc-link audiowrt %s\n' "$repo_root" >> "$sdk/feeds.conf"

  local official_marker="$sdk/.audiowrt-official-feeds-v3-ready"
  if [[ ! -f "$official_marker" ]]; then
    (
      cd "$sdk"
      # Updating feed indexes is enough. Installing every package from every
      # official feed is both slow and wrong: it pollutes Kconfig with tens of
      # thousands of unrelated package symbols and recursive dependencies.
      ./scripts/feeds update -a

      release_series="${release%.*}"
      rust_patch="$repo_root/repository/sdk-patches/$release_series/packages-rust-use-ci-llvm.patch"
      if [[ -f "$rust_patch" && -f feeds/packages/lang/rust/Makefile ]]; then
        echo "Applying SDK patch: $rust_patch" >&2
        patch -d feeds/packages -p1 --forward --batch < "$rust_patch"
      fi
    ) >&2
    touch "$official_marker"
  fi

  printf '%s\n' "$sdk"
}

for context in "${contexts[@]}"; do
  IFS=$'\t' read -r target subtarget <<<"$context"
  sdk="$(prepare_sdk "$target" "$subtarget")"

  mapfile -t packages < <(TASKS_JSON="$tasks_json" TARGET="$target" SUBTARGET="$subtarget" python3 - <<'PY'
import json, os
seen=set()
for t in json.loads(os.environ['TASKS_JSON']):
    if t['target']==os.environ['TARGET'] and t['subtarget']==os.environ['SUBTARGET'] and t['package'] not in seen:
        seen.add(t['package'])
        print(t['package'])
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

  # Install only the AudioWRT sources requested for this context. The feeds
  # helper pulls their declared dependencies as needed; we never install all
  # packages from packages/luci/routing/telephony/video or all AudioWRT sources.
  for package in "${packages[@]}"; do
    (cd "$sdk"; ./scripts/feeds install -f -p audiowrt "$package") >&2 || {
      echo "$package|$target|$subtarget|feed-install-failed" >> "$failures_file"
    }
  done
  (cd "$sdk"; make defconfig) >&2

  targets=()
  for package in "${packages[@]}"; do
    if [[ -e "$sdk/package/feeds/audiowrt/$package" ]]; then
      targets+=("package/feeds/audiowrt/$package/compile")
    else
      echo "$package|$target|$subtarget|not-registered" >> "$failures_file"
    fi
  done

  if ((${#targets[@]})); then
    echo "::group::Build ${#targets[@]} package source(s) / $release / $arch / $target/$subtarget"
    (cd "$sdk"; make -k "${targets[@]}" -j"$jobs" V=s) || true
    echo "::endgroup::"
  fi

  for package in "${packages[@]}"; do
    source_dir=""
    for category in audiowrt ported trimmed tailored; do
      candidate="$repo_root/$category/$package"
      [[ -f "$candidate/Makefile" ]] && { source_dir="$candidate"; break; }
    done
    [[ -n "$source_dir" ]] || { echo "$package|$target|$subtarget|unknown-source" >> "$failures_file"; continue; }

    package_output="$output_root/$package/$release/$arch/$target/$subtarget"
    mkdir -p "$package_output/packages"
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
      continue
    fi

    python3 - "$package_output/context.json" "$package" "$release" "$arch" "$target" "$subtarget" <<'PY'
import json, sys
path, package, release, arch, target, subtarget=sys.argv[1:]
with open(path,'w',encoding='utf-8') as f:
    json.dump({'package_source':package,'openwrt_version':release,'arch':arch,'target':target,'subtarget':subtarget},f,indent=2,sort_keys=True)
    f.write('\n')
PY
    echo "Built $package for OpenWrt $release / $arch / $target/$subtarget"
  done
done

if [[ -s "$failures_file" ]]; then
  echo "Some package outputs were not produced:" >&2
  cat "$failures_file" >&2
fi
