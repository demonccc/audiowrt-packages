#!/usr/bin/env bash
set -euo pipefail

release="${RELEASE:?RELEASE is required}"
arch="${ARCH:?ARCH is required}"
tasks_json="${TASKS_JSON:?TASKS_JSON is required}"
jobs="${MAKE_JOBS:-4}"
: "${CHANNEL:?CHANNEL is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
: "${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}"

mkdir -p output

# Keep one SDK/feed/configuration session for the whole architecture job. The
# build helper invokes the publish hook immediately after each successful task,
# so completed packages remain durable even if a later package fails or the job
# is cancelled.
bash scripts/build-package-batch.sh \
  --release "$release" \
  --arch "$arch" \
  --tasks-json "$tasks_json" \
  --output output \
  --jobs "$jobs" \
  --success-hook scripts/publish-package-output.sh
