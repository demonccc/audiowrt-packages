#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-package-batch.sh --release VERSION --arch ARCH --tasks-json JSON \
  --output DIR [--jobs N] [--cache DIR] [--success-hook SCRIPT]

Build pending package tasks independently. Each package is compiled in its own
clean OpenWrt SDK context through build-package-context.sh. The SDK archive cache
is shared, but generated feed/Kconfig/build state is never shared between tasks.
EOF
}

release=""
arch=""
tasks_json=""
output_root=""
jobs=4
cache="${RUNNER_TEMP:-/tmp}/audiowrt-packages-cache"
success_hook=""

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
mkdir -p "$cache" "$output_root"
cache="$(cd "$cache" && pwd)"
output_root="$(cd "$output_root" && pwd)"
failures_file="$output_root/build-failures.txt"
: > "$failures_file"
source_commit="$(git -C "$repo_root" rev-parse HEAD)"

if [[ -n "$success_hook" ]]; then
  success_hook="$(cd "$(dirname "$success_hook")" && pwd)/$(basename "$success_hook")"
  [[ -f "$success_hook" ]] || { echo "ERROR: success hook not found: $success_hook" >&2; exit 2; }
fi

mapfile -t task_rows < <(TASKS_JSON="$tasks_json" python3 - <<'PY'
import json, os
seen=set()
for task in json.loads(os.environ['TASKS_JSON']):
    key=(task['package'], task['scope'], task['target'], task['subtarget'])
    if key in seen:
        continue
    seen.add(key)
    print('\t'.join(key))
PY
)

for row in "${task_rows[@]}"; do
  IFS=$'\t' read -r package scope target subtarget <<<"$row"
  echo "::group::Task $package / $release / $arch / $target/$subtarget"

  package_output="$output_root/$package/$release/$arch/$target/$subtarget"
  rm -rf "$package_output"
  mkdir -p "$package_output"

  build_log="$package_output/build.log"
  if ! bash "$repo_root/scripts/build-package-context.sh" \
      --package "$package" \
      --release "$release" \
      --arch "$arch" \
      --target "$target" \
      --subtarget "$subtarget" \
      --output "$package_output" \
      --jobs "$jobs" \
      --cache "$cache" >"$build_log" 2>&1; then
    echo "$package|$target|$subtarget|compile-failed" >> "$failures_file"
    echo "ERROR: compile failed for $package; last 120 log lines:" >&2
    tail -n 120 "$build_log" >&2 || true
    echo "::endgroup::"
    continue
  fi

  python3 - "$package_output/context.json" "$scope" "$source_commit" <<'PY'
import json, sys
path, scope, source_commit = sys.argv[1:]
data = json.load(open(path, encoding='utf-8'))
data['scope'] = scope
data['source_commit'] = source_commit
with open(path, 'w', encoding='utf-8') as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write('\n')
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

if [[ -s "$failures_file" ]]; then
  echo "Some package tasks failed; successful outputs were preserved as build artifacts:" >&2
  cat "$failures_file" >&2
  exit 1
fi
