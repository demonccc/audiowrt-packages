#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-package-batch.sh --release VERSION --arch ARCH --tasks-json JSON \
  --output DIR [--jobs N] [--cache DIR] [--success-hook SCRIPT]

Build pending package roots with the canonical AudioWRT package builder. The
AudioWRT repository owns OpenWrt SDK preparation, exact-release feed handling,
dependency ordering, development-interface staging and special kernel/package
preparation. This repository only selects pending roots, captures their APKs
and publishes successful outputs.
EOF
}

release=""; arch=""; tasks_json=""; output_root=""; jobs=4
cache=""; success_hook=""
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
engine_dir="${AUDIOWRT_ENGINE_DIR:-$repo_root/.audiowrt-engine}"
[[ -f "$engine_dir/Makefile" && -f "$engine_dir/scripts/build.sh" ]] || {
  echo "ERROR: canonical AudioWRT build engine is missing at $engine_dir" >&2
  exit 2
}

if [[ -n "$success_hook" ]]; then
  success_hook="$(cd "$(dirname "$success_hook")" && pwd)/$(basename "$success_hook")"
  [[ -f "$success_hook" ]] || { echo "ERROR: success hook not found: $success_hook" >&2; exit 2; }
fi

# The canonical AudioWRT builder mounts CACHE_DIR into Docker and therefore
# requires the cache to live inside the AudioWRT checkout. Keep the default
# cache under the checked-out build engine so GitHub Actions can persist it
# without violating that invariant.
if [[ -z "$cache" ]]; then
  cache="$engine_dir/.cache/audiowrt-packages"
fi

mkdir -p "$cache" "$output_root"
cache="$(cd "$cache" && pwd)"
output_root="$(cd "$output_root" && pwd)"
failures_file="$output_root/build-failures.txt"
: > "$failures_file"
source_commit="$(git -C "$repo_root" rev-parse HEAD)"

profile_for_context() {
  case "$1/$2" in
    ath79/generic) printf 'tplink-tl-wdr4300-v1-minimal-usb-bluetooth-%s\n' "$release" ;;
    ipq40xx/generic) printf 'linksys-ea8300-usb-bluetooth-audio-%s\n' "$release" ;;
    bcm27xx/bcm2709) printf 'raspberry-pi-3-usb-bluetooth-audio-%s\n' "$release" ;;
    bcm27xx/bcm2711) printf 'raspberry-pi-4-usb-bluetooth-audio-%s\n' "$release" ;;
    x86/64) printf 'x86-64-usb-bluetooth-audio-%s\n' "$release" ;;
    *) return 1 ;;
  esac
}

mapfile -t contexts < <(TASKS_JSON="$tasks_json" python3 - <<'PY'
import json, os
seen=set()
for task in json.loads(os.environ['TASKS_JSON']):
    key=(task['target'], task['subtarget'])
    if key not in seen:
        seen.add(key)
        print('\t'.join(key))
PY
)

for context in "${contexts[@]}"; do
  IFS=$'\t' read -r target subtarget <<<"$context"
  if ! profile="$(profile_for_context "$target" "$subtarget")"; then
    echo "ERROR: no canonical AudioWRT profile for $target/$subtarget" >&2
    exit 4
  fi
  [[ -f "$engine_dir/profiles/$profile.yaml" ]] || {
    echo "ERROR: canonical AudioWRT profile does not exist: $profile" >&2
    exit 4
  }

  mapfile -t task_rows < <(TASKS_JSON="$tasks_json" TARGET="$target" SUBTARGET="$subtarget" python3 - <<'PY'
import json, os
seen=set()
for task in json.loads(os.environ['TASKS_JSON']):
    if task['target'] != os.environ['TARGET'] or task['subtarget'] != os.environ['SUBTARGET']:
        continue
    key=(task['package'], task['scope'])
    if key in seen:
        continue
    seen.add(key)
    print('\t'.join(key))
PY
  )
  ((${#task_rows[@]})) || continue

  roots=()
  declare -A pending_scope=()
  for row in "${task_rows[@]}"; do
    IFS=$'\t' read -r package scope <<<"$row"
    roots+=("$package")
    pending_scope["$package"]="$scope"
  done

  echo "::group::Canonical AudioWRT build / $release / $arch / $target/$subtarget"
  echo "Profile: $profile"
  echo "Pending roots: ${roots[*]}"

  engine_cache="$cache/canonical-$release-$target-$subtarget"
  mkdir -p "$engine_cache"
  rm -rf "$engine_dir/output/packages/$profile" "$engine_dir/.work/packages/$profile"

  build_log="$output_root/canonical-$release-$arch-$target-$subtarget.log"
  set +e
  make -C "$engine_dir" packages \
    AUDIOWRT_PROFILE="$profile" \
    PACKAGE="${roots[*]}" \
    AUDIOWRT_PACKAGES_REPOSITORY="https://github.com/${GITHUB_REPOSITORY}.git" \
    AUDIOWRT_PACKAGES_REF="$source_commit" \
    JOBS="$jobs" \
    VERBOSITY=normal \
    CACHE_DIR="$engine_cache" >"$build_log" 2>&1
  build_rc=$?
  set -e

  engine_output="$engine_dir/output/packages/$profile/packages"
  if (( build_rc != 0 )); then
    echo "ERROR: canonical AudioWRT package build failed for $target/$subtarget; last 160 log lines:" >&2
    tail -n 160 "$build_log" >&2 || true
  fi

  for row in "${task_rows[@]}"; do
    IFS=$'\t' read -r package scope <<<"$row"
    echo "::group::Capture $package / $release / $arch / $target/$subtarget"

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

    mapfile -t output_names < <(python3 - "$source_dir/Makefile" <<'PY'
import re, sys
text=open(sys.argv[1], encoding='utf-8').read()
for name in re.findall(r'^define Package/([^\s]+)', text, re.M):
    print(name)
for name in re.findall(r'^define KernelPackage/([^\s]+)', text, re.M):
    print('kmod-'+name)
PY
    )

    found=0
    if [[ -d "$engine_output" ]]; then
      for name in "${output_names[@]}"; do
        while IFS= read -r apk; do
          cp -f "$apk" "$package_output/packages/"
          found=1
        done < <(find "$engine_output" -maxdepth 1 -type f -name "$name-*.apk" -print)
      done
    fi

    if [[ "$found" != 1 ]]; then
      reason="no-apk"
      (( build_rc == 0 )) || reason="canonical-build-failed"
      echo "$package|$target|$subtarget|$reason" >> "$failures_file"
      echo "ERROR: no canonical APK captured for $package" >&2
      echo "::endgroup::"
      continue
    fi

    python3 - "$package_output/context.json" "$package" "$release" "$arch" "$target" "$subtarget" <<'PY'
import json, sys
path, package, release, arch, target, subtarget=sys.argv[1:]
with open(path,'w',encoding='utf-8') as handle:
    json.dump({
        'package_source':package,
        'openwrt_version':release,
        'arch':arch,
        'target':target,
        'subtarget':subtarget,
    }, handle, indent=2, sort_keys=True)
    handle.write('\n')
PY

    echo "Built $package with canonical AudioWRT builder"
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

  echo "::endgroup::"
done

if [[ -s "$failures_file" ]]; then
  echo "Some package tasks failed; successful outputs were already preserved/published:" >&2
  cat "$failures_file" >&2
  exit 1
fi
