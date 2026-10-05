#!/usr/bin/env python3
from pathlib import Path

script = (Path(__file__).resolve().parents[1] / "scripts" / "build-package-context.sh").read_text(encoding="utf-8")

assert "./scripts/feeds install -a" not in script
assert "./scripts/feeds install -p audiowrt -a" not in script
assert 'package/feeds/audiowrt' in script
assert 'resolve-official-sdk-dependencies.py' in script
assert './scripts/feeds install "$dependency"' in script
assert 'make VERSION_NUMBER="$release" -s prepare-tmpinfo' in script
assert 'make VERSION_NUMBER="$release" defconfig' in script
assert 'make VERSION_NUMBER="$release" "$target_path" -j"$jobs" V=s' in script
assert 'NO_DEPS=1 -j"$jobs"' not in script

print("SDK source registration and dependency staging test passed")
