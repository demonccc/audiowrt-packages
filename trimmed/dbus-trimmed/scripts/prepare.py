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
OMIT = {
    Path("usr/bin/dbus-cleanup-sockets"),
    Path("usr/bin/dbus-launch"),
    Path("usr/bin/dbus-launch.real"),
}
REQUIRED = {
    Path("usr/bin/dbus-daemon"),
    Path("usr/bin/dbus-uuidgen"),
    Path("usr/lib/dbus-daemon-launch-helper"),
    Path("etc/init.d/dbus"),
    Path("etc/capabilities/dbus.json"),
    Path("usr/share/dbus-1"),
}


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def package_base(release: str, arch: str) -> str:
    if release == "SNAPSHOT" or release == "snapshot":
        return f"{OPENWRT_DOWNLOADS}/snapshots/packages/{arch}/packages/"
    if not re.fullmatch(r"\d+\.\d+\.\d+", release):
        fail(f"unsupported OpenWrt VERSION_NUMBER: {release}")
    return f"{OPENWRT_DOWNLOADS}/releases/{release}/packages/{arch}/packages/"


def resolve_dbus_apk(base: str) -> str:
    try:
        with urllib.request.urlopen(base) as response:
            listing = response.read().decode("utf-8")
    except OSError as exc:
        fail(f"could not read OpenWrt package directory {base}: {exc}")

    matches = list(
        dict.fromkeys(
            unescape(value)
            for value in re.findall(r'href="(dbus-[0-9][^"]*\.apk)"', listing)
        )
    )
    if len(matches) != 1:
        fail(f"expected one dbus APK in {base}, found {len(matches)}: {', '.join(matches)}")
    return urljoin(base, matches[0])


def download(url: str, destination: Path) -> None:
    try:
        with urllib.request.urlopen(url) as response, destination.open("wb") as handle:
            shutil.copyfileobj(response, handle)
    except OSError as exc:
        fail(f"could not download {url}: {exc}")


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
    url = resolve_dbus_apk(base)

    with tempfile.TemporaryDirectory(prefix="audiowrt-dbus-") as temp_name:
        temp = Path(temp_name)
        archive = temp / Path(url).name
        extracted = temp / "extracted"
        extracted.mkdir()
        download(url, archive)

        subprocess.run(
            [str(apk_tool), "--allow-untrusted", "extract", "--destination", str(extracted), str(archive)],
            check=True,
        )

        missing = [str(path) for path in sorted(REQUIRED) if not (extracted / path).exists()]
        if missing:
            fail("official dbus APK is missing required payload: " + ", ".join(missing))

        args.output.mkdir(parents=True, exist_ok=True)
        for root_name in ("etc", "usr"):
            source = extracted / root_name
            if source.exists():
                shutil.copytree(source, args.output / root_name, symlinks=True, dirs_exist_ok=True)

    for path in OMIT:
        target = args.output / path
        if target.exists() or target.is_symlink():
            target.unlink()

    leaked = [str(path) for path in sorted(OMIT) if (args.output / path).exists() or (args.output / path).is_symlink()]
    if leaked:
        fail("trimmed D-Bus payload still contains omitted tools: " + ", ".join(leaked))

    for path in REQUIRED:
        if not (args.output / path).exists():
            fail(f"required D-Bus payload disappeared after staging: {path}")

    print(f"AudioWRT D-Bus payload staged from {url}")


if __name__ == "__main__":
    main()
