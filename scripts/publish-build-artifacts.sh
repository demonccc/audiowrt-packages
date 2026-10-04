#!/usr/bin/env bash
set -euo pipefail

root="${1:-artifacts}"
[[ -d "$root" ]] || { echo "ERROR: artifact root not found: $root" >&2; exit 2; }

mapfile -d '' contexts < <(find "$root" -type f -name context.json -print0 | sort -z)
((${#contexts[@]})) || { echo "ERROR: no build package contexts found under $root" >&2; exit 2; }

published=0
for context in "${contexts[@]}"; do
  package_output="$(dirname "$context")"
  [[ -d "$package_output/packages" ]] || continue
  compgen -G "$package_output/packages/*.apk" >/dev/null || continue

  mapfile -t fields < <(python3 - "$context" <<'PY'
import json, sys
ctx=json.load(open(sys.argv[1], encoding='utf-8'))
for key in ('package_source','scope','openwrt_version','arch','target','subtarget','source_commit'):
    value=ctx.get(key)
    if not value:
        raise SystemExit(f"ERROR: build artifact context missing {key}: {sys.argv[1]}")
    print(value)
PY
  )

  package="${fields[0]}"
  scope="${fields[1]}"
  release="${fields[2]}"
  arch="${fields[3]}"
  target="${fields[4]}"
  subtarget="${fields[5]}"
  source_commit="${fields[6]}"

  echo "::group::Publish testing / $package / $release / $arch / $target/$subtarget"
  PACKAGE_NAME="$package" \
  PACKAGE_SCOPE="$scope" \
  PACKAGE_OUTPUT="$package_output" \
  RELEASE="$release" \
  ARCH="$arch" \
  TARGET="$target" \
  SUBTARGET="$subtarget" \
  CHANNEL=testing \
  SOURCE_COMMIT="$source_commit" \
    bash scripts/publish-package-output.sh
  published=$((published + 1))
  echo "::endgroup::"
done

((published > 0)) || { echo "ERROR: no successful package artifacts were publishable" >&2; exit 1; }
echo "Published $published package build output(s) to testing"
