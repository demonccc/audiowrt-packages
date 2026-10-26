#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-package-batch.sh --release VERSION --arch ARCH --tasks-json JSON \
  --output DIR [--jobs N] [--cache DIR] [--success-hook SCRIPT]

Build pending package tasks grouped by target/subtarget. Every package root for
the same release + architecture + target/subtarget is compiled in one clean
OpenWrt SDK context, matching the shared state used by AudioWRT snapshot builds.
Different target/subtarget contexts remain isolated.
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

mapfile -t context_rows < <(TASKS_JSON="$tasks_json" python3 - <<'PY'
import collections
import json
import os

groups = collections.OrderedDict()
seen = set()
for task in json.loads(os.environ['TASKS_JSON']):
    key = (task['package'], task['scope'], task['target'], task['subtarget'])
    if key in seen:
        continue
    seen.add(key)
    context = (task['target'], task['subtarget'])
    groups.setdefault(context, []).append((task['package'], task['scope']))

for (target, subtarget), packages in groups.items():
    encoded = ','.join(f'{package}|{scope}' for package, scope in packages)
    print(f'{target}\t{subtarget}\t{encoded}')
PY
)

for context_row in "${context_rows[@]}"; do
  IFS=$'\t' read -r target subtarget package_scope_csv <<<"$context_row"
  IFS=',' read -r -a package_scope_pairs <<<"$package_scope_csv"

  package_args=()
  packages=()
  scopes=()
  for pair in "${package_scope_pairs[@]}"; do
    package="${pair%%|*}"
    scope="${pair#*|}"
    package_args+=(--package "$package")
    packages+=("$package")
    scopes+=("$scope")
  done

  echo "::group::Context $release / $arch / $target/$subtarget"
  printf 'Shared SDK roots:\n'
  printf '  %s\n' "${packages[@]}"

  safe_context="${target//\//-}-${subtarget//\//-}"
  context_output="$output_root/.context-$safe_context"
  context_log="$output_root/.context-$safe_context.log"
  rm -rf "$context_output"
  mkdir -p "$context_output"

  if ! bash "$repo_root/scripts/build-package-context.sh" \
      "${package_args[@]}" \
      --release "$release" \
      --arch "$arch" \
      --target "$target" \
      --subtarget "$subtarget" \
      --output "$context_output" \
      --jobs "$jobs" \
      --cache "$cache" 2>&1 | tee "$context_log"; then
    echo "ERROR: shared SDK setup/build failed for $target/$subtarget; last 120 log lines:" >&2
    tail -n 120 "$context_log" >&2 || true
    for package in "${packages[@]}"; do
      package_output="$output_root/$package/$release/$arch/$target/$subtarget"
      rm -rf "$package_output"
      mkdir -p "$package_output"
      cp -f "$context_log" "$package_output/build.log"
      echo "$package|$target|$subtarget|context-failed" >> "$failures_file"
    done
    rm -rf "$context_output"
    echo "::endgroup::"
    continue
  fi

  for index in "${!packages[@]}"; do
    package="${packages[$index]}"
    scope="${scopes[$index]}"
    package_output="$output_root/$package/$release/$arch/$target/$subtarget"
    rm -rf "$package_output"
    mkdir -p "$package_output"

    if [[ -d "$context_output/$package" ]]; then
      cp -a "$context_output/$package/." "$package_output/"
    fi
    cp -f "$context_log" "$package_output/build.log"

    if [[ ! -s "$package_output/context.json" ]] ||
       ! compgen -G "$package_output/packages/*.apk" > /dev/null; then
      echo "$package|$target|$subtarget|compile-failed" >> "$failures_file"
      echo "ERROR: shared SDK did not produce $package" >&2
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
      fi
    fi
  done

  rm -rf "$context_output"
  echo "::endgroup::"
done

if [[ -s "$failures_file" ]]; then
  echo "Some package tasks failed; successful outputs were preserved as build artifacts:" >&2
  cat "$failures_file" >&2
  exit 1
fi
