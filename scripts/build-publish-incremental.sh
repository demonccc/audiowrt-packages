#!/usr/bin/env bash
set -euo pipefail

release="${RELEASE:?RELEASE is required}"
arch="${ARCH:?ARCH is required}"
tasks_json="${TASKS_JSON:?TASKS_JSON is required}"
channel="${CHANNEL:?CHANNEL is required}"
jobs="${MAKE_JOBS:-4}"
repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
source_commit="${GITHUB_SHA:?GITHUB_SHA is required}"

mkdir -p output
failures=0

mapfile -t tasks < <(TASKS_JSON="$tasks_json" python3 - <<'PY'
import json, os
for task in json.loads(os.environ['TASKS_JSON']):
    print(json.dumps(task, separators=(',', ':')))
PY
)

for task_json in "${tasks[@]}"; do
  IFS=$'\t' read -r package scope target subtarget < <(TASK_JSON="$task_json" python3 - <<'PY'
import json, os
t=json.loads(os.environ['TASK_JSON'])
print('\t'.join((t['package'], t['scope'], t['target'], t['subtarget'])))
PY
  )

  echo "::group::Task $package / $release / $arch / $target/$subtarget"
  if ! bash scripts/build-package-batch.sh \
      --release "$release" \
      --arch "$arch" \
      --tasks-json "[$task_json]" \
      --output output \
      --jobs "$jobs"; then
    echo "ERROR: build helper failed for $package / $arch / $target/$subtarget" >&2
    failures=$((failures + 1))
    echo "::endgroup::"
    continue
  fi

  output="output/${package}/${release}/${arch}/${target}/${subtarget}"
  if [[ ! -d "$output/packages" ]] || ! compgen -G "$output/packages/*.apk" >/dev/null; then
    echo "ERROR: no successful output for $package / $arch / $target/$subtarget" >&2
    failures=$((failures + 1))
    echo "::endgroup::"
    continue
  fi

  short_sha="${source_commit:0:12}"
  safe_target="${target}-${subtarget}"
  tag="packages-${channel}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-${package}-${release}-${arch}-${safe_target}-${short_sha}"

  if ! python3 scripts/create-repository-update.py \
      --packages-dir "$output/packages" \
      --context "$output/context.json" \
      --scope "$scope" \
      --channel "$channel" \
      --release-tag "$tag" \
      --repository "$repository" \
      --source-commit "$source_commit" \
      --output "$output/repository-update.json"; then
    echo "ERROR: failed to create repository metadata for $package / $arch" >&2
    failures=$((failures + 1))
    echo "::endgroup::"
    continue
  fi

  args=(release create "$tag" "$output"/packages/*.apk "$output/repository-update.json"
    --repo "$repository"
    --target "$source_commit"
    --title "$tag"
    --notes "AudioWRT ${package} for OpenWrt ${release} / ${arch} / ${target}/${subtarget}")
  if [[ "$channel" == testing ]]; then
    args+=(--prerelease)
  fi

  if ! gh "${args[@]}"; then
    echo "ERROR: failed to publish $package for $arch" >&2
    failures=$((failures + 1))
    echo "::endgroup::"
    continue
  fi

  echo "Published $package for OpenWrt $release / $arch / $target/$subtarget"
  echo "::endgroup::"
done

if (( failures > 0 )); then
  echo "ERROR: $failures task(s) failed; successful tasks were already published and will not be rebuilt next time." >&2
  exit 1
fi
