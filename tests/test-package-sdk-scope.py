#!/usr/bin/env python3
from pathlib import Path

script = (Path(__file__).resolve().parents[1] / "scripts" / "build-package-context.sh").read_text(encoding="utf-8")

assert "./scripts/feeds install -a" not in script
assert "./scripts/feeds install -p audiowrt -a" in script
assert 'make VERSION_NUMBER="$release" defconfig' in script
assert 'make VERSION_NUMBER="$release" "$target_path" -j"$jobs" V=s' in script
assert 'make VERSION_NUMBER="$release" "$target_path" NO_DEPS=1 -j"$jobs" V=s' in script

print("SDK feed scope and release propagation test passed")
