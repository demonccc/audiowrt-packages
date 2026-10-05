#!/usr/bin/env python3
from pathlib import Path

script = (Path(__file__).resolve().parents[1] / "scripts" / "build-package-context.sh").read_text(encoding="utf-8")

assert "./scripts/feeds install -a" not in script
assert "./scripts/feeds install -p audiowrt -a" not in script
assert 'package/feeds/audiowrt' in script
assert 'resolve-source-build-dependencies.py' in script
assert './scripts/feeds install "${source_dependencies[@]}"' in script
assert 'package/toolchain/compile NO_DEPS=1' in script
assert 'CONFIG_PACKAGE_${name}=m' in script
assert 'CONFIG_PACKAGE_${name}=n' in script
assert 'NO_DEPS=1 -j"$jobs"' in script
assert 'CONFIG_PACKAGE_kmod-bluetooth=n' in script
assert 'CONFIG_PACKAGE_kmod-bluetooth-trimmed=n' in script
assert 'make VERSION_NUMBER="$release"' in script

print("Proven AudioWRT SDK package model test passed")
