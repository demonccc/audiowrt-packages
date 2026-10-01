#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import tempfile
import urllib.request
from html import unescape
from pathlib import Path
from urllib.parse import urljoin

OPENWRT_DOWNLOADS = "https://downloads.openwrt.org"
KEEP_PREFIXES = (
    "libglib-2.0.so",
    "libgobject-2.0.so",
    "libgmodule-2.0.so",
    "libgio-2.0.so",
)
DROP_PREFIXES = (
    "libgirepository-2.0.so",
    "libgthread-2.0.so",
)


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def package_base(release: str, arch: str) -> str:
    if release.lower() == "snapshot":
        return f"{OPENWRT_DOWNLOADS}/snapshots/packages/{arch}/packages/"
    if not re.fullmatch(r"\d+\.\d+\.\d+", release):
        fail(f"unsupported OpenWrt VERSION_NUMBER: {release}")
    return f"{OPENWRT_DOWNLOADS}/releases/{release}/packages/{arch}/packages/"


def resolve_glib2_apk(base: str) -> str:
    try:
        with urllib.request.urlopen(base) as response:
            listing = response.read().decode("utf-8")
    except OSError as exc:
        fail(f"could not read OpenWrt package directory {base}: {exc}")

    matches = list(
        dict.fromkeys(
            unescape(value)
            for value in re.findall(r'href="(glib2-[0-9][^"]*\.apk)"', listing)
        )
    )
    if len(matches) != 1:
        fail(f"expected one glib2 APK in {base}, found {len(matches)}: {', '.join(matches)}")
    return urljoin(base, matches[0])


def download(url: str, destination: Path) -> None:
    try:
        with urllib.request.urlopen(url) as response, destination.open("wb") as handle:
            shutil.copyfileobj(response, handle)
    except OSError as exc:
        fail(f"could not download {url}: {exc}")


def matching_files(libdir: Path, prefixes: tuple[str, ...]) -> list[Path]:
    return sorted(
        path for path in libdir.iterdir()
        if path.is_file() or path.is_symlink()
        if any(path.name.startswith(prefix) for prefix in prefixes)
    )


def apparent_size(paths: list[Path]) -> int:
    total = 0
    seen: set[Path] = set()
    for path in paths:
        try:
            target = path.resolve(strict=True)
        except FileNotFoundError:
            continue
        if target in seen:
            continue
        seen.add(target)
        total += target.stat().st_size
    return total


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", required=True)
    parser.add_argument("--arch", required=True)
    parser.add_argument("--apk", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    if not re.fullmatch(r"[A-Za-z0-9_.+-]+", args.arch):
        fail(f"invalid package architecture: {args.arch}")

    apk_tool = Path(args.apk)
    if not apk_tool.is_file():
        fail(f"OpenWrt host apk tool is missing: {apk_tool}")

    base = package_base(args.release, args.arch)
    url = resolve_glib2_apk(base)

    with tempfile.TemporaryDirectory(prefix="audiowrt-glib2-") as temp_name:
        temp = Path(temp_name)
        archive = temp / Path(url).name
        extracted = temp / "extracted"
        extracted.mkdir()
        download(url, archive)

        subprocess.run(
            [str(apk_tool), "--allow-untrusted", "extract", "--destination", str(extracted), str(archive)],
            check=True,
        )

        libdir = extracted / "usr/lib"
        if not libdir.is_dir():
            fail("official glib2 APK has no usr/lib payload")

        kept = matching_files(libdir, KEEP_PREFIXES)
        dropped = matching_files(libdir, DROP_PREFIXES)
        missing = [prefix for prefix in KEEP_PREFIXES if not any(path.name.startswith(prefix) for path in kept)]
        if missing:
            fail("official glib2 APK is missing required runtime libraries: " + ", ".join(missing))

        unexpected = sorted(
            path.name for path in libdir.iterdir()
            if (path.is_file() or path.is_symlink())
            and path.name.startswith("libg")
            and not any(path.name.startswith(prefix) for prefix in KEEP_PREFIXES + DROP_PREFIXES)
        )
        if unexpected:
            fail("unclassified GLib runtime libraries found: " + ", ".join(unexpected))

        out_lib = args.output / "usr/lib"
        out_lib.mkdir(parents=True, exist_ok=True)
        for path in kept:
            destination = out_lib / path.name
            if path.is_symlink():
                destination.symlink_to(path.readlink())
            else:
                shutil.copy2(path, destination)

        retained_bytes = apparent_size(kept)
        removed_bytes = apparent_size(dropped)
        original_bytes = retained_bytes + removed_bytes

        print(f"AudioWRT GLib2 payload staged from {url}")
        print(f"retained runtime bytes: {retained_bytes}")
        print(f"removed runtime bytes: {removed_bytes}")
        print(f"original classified runtime bytes: {original_bytes}")
        if original_bytes:
            print(f"runtime reduction: {removed_bytes * 100.0 / original_bytes:.1f}%")
        if dropped:
            print("removed libraries:")
            for path in dropped:
                print(f"  {path.name}")


if __name__ == "__main__":
    main()
