#!/usr/bin/env python3
"""Prepare exact-release OpenWrt metadata/source/files/patches for an AudioWRT package.

The caller owns only the AudioWRT recipe body. Version, source, hash, build
flags, canonical source overlays, runtime files and OpenWrt patches are inherited
from the package recipe that exists in the selected OpenWrt SDK/feed checkout.
AudioWRT patches may additionally be scoped by package architecture or
OpenWrt target/subtarget.
"""

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

PACKAGE_MK = re.compile(r"^\s*include\s+\$\(INCLUDE_DIR\)/package\.mk\s*$")
TOPDIR_RULES = re.compile(r"^\s*include\s+\$\(TOPDIR\)/rules\.mk\s*$")
VERSION_FALLBACK = re.compile(
    r"^\s*VERSION_NUMBER\s*:=\s*\$\(if\s+\$\(VERSION_NUMBER\),"
    r"\$\(VERSION_NUMBER\),([^\)]+)\)\s*$"
)


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def resolve_openwrt_version(version: str, topdir: Path) -> str:
    value = version.strip()
    if value:
        return value

    version_mk = topdir / "include" / "version.mk"
    if not version_mk.is_file():
        fail(
            "OpenWrt VERSION_NUMBER is empty and include/version.mk is missing "
            f"under {topdir}"
        )

    for line in version_mk.read_text(encoding="utf-8").splitlines():
        match = VERSION_FALLBACK.match(line)
        if match:
            value = match.group(1).strip()
            if value:
                return value

    fail(
        "OpenWrt VERSION_NUMBER is empty and the selected tree/SDK does not "
        f"expose a release fallback in {version_mk}"
    )


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
            fail(f"AudioWRT patch collides with canonical/AudioWRT patch: {target}")
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(patch, target)


def overlay_context_patches(
    root: Path,
    destination: Path,
    arch: str,
    target: str,
    subtarget: str,
) -> None:
    """Overlay common, architecture and target-specific AudioWRT patches.

    Existing patches directly under patches/ remain common. New scoped layouts:
      patches/arch/<arch>/*.patch
      patches/target/<target>/<subtarget>/*.patch
    The same layout is valid below releases/<major.minor>/patches/.
    """
    overlay_patches(root, destination)
    if arch:
        overlay_patches(root / "arch" / arch, destination)
    if target and subtarget:
        overlay_patches(root / "target" / target / subtarget, destination)


def main() -> int:
    if len(sys.argv) != 14:
        print(
            "usage: prepare-openwrt-derived.py <canonical-makefile> <delta-root> "
            "<openwrt-version> <openwrt-topdir> <arch-packages> <target> "
            "<subtarget> <preamble-out> <release-recipe-out> <patch-dir> "
            "<files-dir> <src-dir> <stamp>",
            file=sys.stderr,
        )
        return 2

    canonical_makefile = Path(sys.argv[1]).resolve()
    delta_root = Path(sys.argv[2]).resolve()
    topdir = Path(sys.argv[4]).resolve()
    version = resolve_openwrt_version(sys.argv[3], topdir)
    arch = sys.argv[5].strip()
    target = sys.argv[6].strip()
    subtarget = sys.argv[7].strip()
    preamble_out = Path(sys.argv[8])
    release_recipe_out = Path(sys.argv[9])
    patch_dir = Path(sys.argv[10])
    files_dir = Path(sys.argv[11])
    src_dir = Path(sys.argv[12])
    stamp = Path(sys.argv[13])

    if not canonical_makefile.is_file():
        fail(f"canonical OpenWrt recipe is missing: {canonical_makefile}")
    if not delta_root.is_dir():
        fail(f"AudioWRT delta directory is missing: {delta_root}")

    release_family = family(version)
    canonical_root = canonical_makefile.parent
    release_delta = delta_root / "releases" / release_family

    preamble_out.parent.mkdir(parents=True, exist_ok=True)
    preamble_out.write_text(extract_preamble(canonical_makefile), encoding="utf-8")

    release_recipe_out.parent.mkdir(parents=True, exist_ok=True)
    recipe_fragment = release_delta / "recipe.mk"
    if recipe_fragment.is_file():
        release_recipe_out.write_text(recipe_fragment.read_text(encoding="utf-8"), encoding="utf-8")
    else:
        release_recipe_out.write_text(
            f"# No AudioWRT recipe override for OpenWrt {release_family}\n",
            encoding="utf-8",
        )

    shutil.rmtree(patch_dir, ignore_errors=True)
    shutil.rmtree(files_dir, ignore_errors=True)
    shutil.rmtree(src_dir, ignore_errors=True)
    patch_dir.mkdir(parents=True, exist_ok=True)
    files_dir.mkdir(parents=True, exist_ok=True)
    src_dir.mkdir(parents=True, exist_ok=True)

    copy_tree(canonical_root / "patches", patch_dir)
    copy_tree(canonical_root / "files", files_dir)
    copy_tree(canonical_root / "src", src_dir)

    copy_tree(delta_root / "files", files_dir)
    copy_tree(delta_root / "src", src_dir)
    overlay_context_patches(delta_root / "patches", patch_dir, arch, target, subtarget)

    copy_tree(release_delta / "files", files_dir)
    copy_tree(release_delta / "src", src_dir)
    overlay_context_patches(release_delta / "patches", patch_dir, arch, target, subtarget)

    stamp.parent.mkdir(parents=True, exist_ok=True)
    stamp.write_text(
        f"canonical={canonical_makefile}\n"
        f"openwrt_version={version}\n"
        f"release_family={release_family}\n"
        f"arch={arch}\n"
        f"target={target}\n"
        f"subtarget={subtarget}\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
