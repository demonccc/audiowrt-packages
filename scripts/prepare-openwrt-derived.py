#!/usr/bin/env python3
"""Prepare exact-release OpenWrt metadata/files/patches for an AudioWRT package.

The caller owns only the AudioWRT recipe body. Version, source, hash, build
flags, canonical runtime files and OpenWrt source patches are inherited from
the package recipe that exists in the selected OpenWrt SDK/feed checkout.
"""

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

PACKAGE_MK = re.compile(r"^\s*include\s+\$\(INCLUDE_DIR\)/package\.mk\s*$")
TOPDIR_RULES = re.compile(r"^\s*include\s+\$\(TOPDIR\)/rules\.mk\s*$")


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def family(version: str) -> str:
    value = version.strip()
    if value.lower() in {"snapshot", "snapshots"}:
        return "snapshot"
    match = re.search(r"(\d+)\.(\d+)", value)
    if not match:
        fail(f"cannot derive OpenWrt release family from {version!r}")
    return f"{match.group(1)}.{match.group(2)}"


def extract_preamble(makefile: Path) -> str:
    lines = makefile.read_text(encoding="utf-8").splitlines(keepends=True)
    package_index = None
    rules_index = None
    for index, line in enumerate(lines):
        stripped = line.rstrip("\n")
        if rules_index is None and TOPDIR_RULES.match(stripped):
            rules_index = index
        if PACKAGE_MK.match(stripped):
            package_index = index
            break
    if package_index is None:
        fail(f"canonical recipe has no package.mk include: {makefile}")
    start = (rules_index + 1) if rules_index is not None else 0
    return "".join(lines[start:package_index]).lstrip("\n").rstrip() + "\n"


def copy_tree(source: Path, destination: Path) -> None:
    if not source.is_dir():
        return
    for item in source.rglob("*"):
        if item.is_dir():
            continue
        relative = item.relative_to(source)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, target)


def overlay_patches(source: Path, destination: Path) -> None:
    if not source.is_dir():
        return
    for patch in source.iterdir():
        if not patch.is_file():
            continue
        if not re.match(r"9\d\d-", patch.name):
            fail(
                f"AudioWRT patch {patch} must use the 9xx namespace; "
                "OpenWrt-owned patches belong only to the canonical recipe"
            )
        target = destination / patch.name
        if target.exists():
            fail(f"AudioWRT patch collides with canonical patch: {target}")
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(patch, target)


def main() -> int:
    if len(sys.argv) != 8:
        print(
            "usage: prepare-openwrt-derived.py <canonical-makefile> <delta-root> "
            "<openwrt-version> <preamble-out> <patch-dir> <files-dir> <stamp>",
            file=sys.stderr,
        )
        return 2

    canonical_makefile = Path(sys.argv[1]).resolve()
    delta_root = Path(sys.argv[2]).resolve()
    version = sys.argv[3]
    preamble_out = Path(sys.argv[4])
    patch_dir = Path(sys.argv[5])
    files_dir = Path(sys.argv[6])
    stamp = Path(sys.argv[7])

    if not canonical_makefile.is_file():
        fail(f"canonical OpenWrt recipe is missing: {canonical_makefile}")
    if not delta_root.is_dir():
        fail(f"AudioWRT delta directory is missing: {delta_root}")

    release_family = family(version)
    canonical_root = canonical_makefile.parent

    preamble_out.parent.mkdir(parents=True, exist_ok=True)
    preamble_out.write_text(extract_preamble(canonical_makefile), encoding="utf-8")

    shutil.rmtree(patch_dir, ignore_errors=True)
    shutil.rmtree(files_dir, ignore_errors=True)
    patch_dir.mkdir(parents=True, exist_ok=True)
    files_dir.mkdir(parents=True, exist_ok=True)

    # OpenWrt owns the base patch and file sets. They always come from the exact
    # canonical recipe selected by the SDK/feed checkout.
    copy_tree(canonical_root / "patches", patch_dir)
    copy_tree(canonical_root / "files", files_dir)

    # AudioWRT overlays are intentionally small. Source patches use 9xx names so
    # it is impossible to silently replace an OpenWrt-owned patch.
    copy_tree(delta_root / "files", files_dir)
    overlay_patches(delta_root / "patches", patch_dir)

    release_delta = delta_root / "releases" / release_family
    copy_tree(release_delta / "files", files_dir)
    overlay_patches(release_delta / "patches", patch_dir)

    stamp.parent.mkdir(parents=True, exist_ok=True)
    stamp.write_text(
        f"canonical={canonical_makefile}\nrelease_family={release_family}\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
