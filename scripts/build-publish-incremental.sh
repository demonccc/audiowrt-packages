#!/usr/bin/env bash
set -euo pipefail

release="${RELEASE:?RELEASE is required}"
arch="${ARCH:?ARCH is required}"
tasks_json="${TASKS_JSON:?TASKS_JSON is required}"
jobs="${MAKE_JOBS:-4}"

mkdir -p output

# Build only. Publication is deliberately a separate manual workflow so the
# exact artifacts produced here can be tested before they enter the testing
# package repository. Successful package outputs are retained even when a
# later package in the same architecture fails.
bash scripts/build-package-batch.sh \
  --release "$release" \
  --arch "$arch" \
  --tasks-json "$tasks_json" \
  --output output \
  --jobs "$jobs"
