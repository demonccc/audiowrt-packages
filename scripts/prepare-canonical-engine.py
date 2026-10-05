#!/usr/bin/env python3
"""Apply package-mode compatibility fixes to the pinned AudioWRT build engine.

The package repository intentionally pins a known AudioWRT engine commit. These
fixes bridge assumptions that are valid for firmware profiles but not for the
architecture/target package matrix. Every replacement is exact and fails closed
if the pinned engine changes unexpectedly.
"""
from __future__ import annotations

import sys
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"ERROR: expected exactly one compatibility anchor in {path}: {old!r}; found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: prepare-canonical-engine.py <audiowrt-checkout>")

    engine = Path(sys.argv[1]).resolve()
    build = engine / "scripts" / "build.sh"
    resolver = engine / "scripts" / "resolve-platform.py"
    if not build.is_file() or not resolver.is_file():
        raise SystemExit(f"ERROR: invalid AudioWRT engine checkout: {engine}")

    replace_once(
        resolver,
        '    if len(sys.argv) != 3:\n        fail("usage: resolve-platform.py <tmp/.targetinfo> <platform>")\n\n    metadata_path = Path(sys.argv[1])\n    platform = sys.argv[2]\n',
        '    if len(sys.argv) not in (3, 5):\n        fail("usage: resolve-platform.py <tmp/.targetinfo> <platform> [target subtarget]")\n\n    metadata_path = Path(sys.argv[1])\n    platform = sys.argv[2]\n    expected_target = sys.argv[3] if len(sys.argv) == 5 else None\n    expected_subtarget = sys.argv[4] if len(sys.argv) == 5 else None\n',
    )
    replace_once(
        resolver,
        '    flush_profile()\n\n    if not matches:\n',
        '    flush_profile()\n\n    if expected_target is not None:\n        matches = [\n            match for match in matches\n            if match["target"] == expected_target and match["subtarget"] == expected_subtarget\n        ]\n\n    if not matches:\n',
    )

    replace_once(
        build,
        'python3 "$repo_root/scripts/resolve-platform.py" "$source_dir/tmp/.targetinfo" "$platform" > "$platform_metadata"',
        'python3 "$repo_root/scripts/resolve-platform.py" "$source_dir/tmp/.targetinfo" "$platform" "$expected_target" "$expected_subtarget" > "$platform_metadata"',
    )
    replace_once(
        build,
        'bluetooth_module_source="$sdk_dir/feeds/audiowrt/kmod-bluetooth-trimmed"',
        'bluetooth_module_source="$sdk_dir/feeds/audiowrt/trimmed/kmod-bluetooth-trimmed"',
    )

    print("Prepared canonical AudioWRT engine for target-scoped package builds")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
