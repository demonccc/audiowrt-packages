#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

from __future__ import annotations

import re
import sys
import urllib.request
from html import unescape
from urllib.parse import urljoin

OPENWRT_DOWNLOADS = "https://downloads.openwrt.org"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def read_listing(url: str) -> str:
    try:
        with urllib.request.urlopen(url) as response:
            return response.read().decode("utf-8")
    except OSError as exc:
        fail(f"could not read OpenWrt package directory: {url}: {exc}")


def main() -> None:
    if len(sys.argv) != 5:
        fail(
            "usage: resolve-openwrt-package.py "
            "<release|snapshot> <arch-packages> <feed> <package>"
        )

    release, arch, feed, package = sys.argv[1:]
    if release != "snapshot" and not re.fullmatch(r"\d+\.\d+\.\d+", release):
        fail("release must be an exact version or snapshot")
    if not re.fullmatch(r"[A-Za-z0-9_.+-]+", arch):
        fail("invalid package architecture")
    if feed != "auto" and not re.fullmatch(r"[A-Za-z0-9_.+-]+", feed):
        fail("invalid feed")
    if not re.fullmatch(r"[A-Za-z0-9_.+-]+", package):
        fail("invalid package name")

    feeds = [feed] if feed != "auto" else ["base", "packages", "luci", "routing", "telephony"]
    found: list[str] = []
    searched: list[str] = []

    # OpenWrt ABI libraries append a numeric ABI to the package name, e.g.
    # libubox20260213. Require the version portion after '-' to start with a
    # digit so sibling packages such as libubox-lua are never selected.
    pattern = re.compile(
        rf'href="({re.escape(package)}(?:[0-9]+)?-[0-9][^"]*\.apk)"'
    )

    for candidate_feed in feeds:
        if release == "snapshot":
            base = f"{OPENWRT_DOWNLOADS}/snapshots/packages/{arch}/{candidate_feed}/"
        else:
            base = f"{OPENWRT_DOWNLOADS}/releases/{release}/packages/{arch}/{candidate_feed}/"
        searched.append(base)
        try:
            listing = read_listing(base)
        except SystemExit:
            if feed != "auto":
                raise
            continue
        matches = list(dict.fromkeys(unescape(value) for value in pattern.findall(listing)))
        found.extend(urljoin(base, value) for value in matches)

    found = list(dict.fromkeys(found))
    if len(found) != 1:
        fail(
            f"expected one {package} APK across {', '.join(searched)}, "
            f"found {len(found)}: " + ", ".join(found)
        )

    print(found[0])


if __name__ == "__main__":
    main()
