#!/usr/bin/env bash
set -euo pipefail
bash -n scripts/build-package-batch.sh
grep -q 'make -k "${targets\[@\]}"' scripts/build-package-batch.sh
grep -q 'feeds update -a' scripts/build-package-batch.sh
grep -q 'audiowrt-official-feeds-ready' scripts/build-package-batch.sh
