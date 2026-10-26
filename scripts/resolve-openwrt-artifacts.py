#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

from __future__ import annotations

import json
import re
import sys
import urllib.request
from html import unescape
from urllib.parse import urljoin

OPENWRT_DOWNLOADS = "https://downloads.openwrt.org"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def resolve_artifact(base_url: str, release: str, target: str, subtarget: str, artifact: str) -> str:
    try:
        with urllib.request.urlopen(base_url) as response:
            listing = response.read().decode("utf-8")
    except OSError as exc:
        fail(f"could not read OpenWrt downloads directory: {base_url}: {exc}")

    target_re, subtarget_re = map(re.escape, (target, subtarget))
    if artifact == "sdk":
        if release == "snapshot":
            pattern = rf'href="([^"]*openwrt-sdk-{target_re}-{subtarget_re}_[^"]+\.Linux-x86_64\.tar\.zst)"'
        else:
            release_re = re.escape(release)
            pattern = rf'href="([^"]*openwrt-sdk-{release_re}-{target_re}-{subtarget_re}_[^"]+\.Linux-x86_64\.tar\.zst)"'
    elif artifact == "imagebuilder":
        prefix = "" if release == "snapshot" else f"{re.escape(release)}-"
        pattern = rf'href="([^"]*openwrt-imagebuilder-{prefix}{target_re}-{subtarget_re}\.Linux-x86_64\.tar\.zst)"'
    else:
        fail(f"unsupported artifact type: {artifact}")

    matches = list(dict.fromkeys(unescape(value) for value in re.findall(pattern, listing)))
    if len(matches) != 1:
        fail(f"expected one {artifact} for {release}/{target}/{subtarget}, found {len(matches)}")
    return urljoin(base_url, matches[0])


def read_listing(url: str) -> str:
    try:
        with urllib.request.urlopen(url) as response:
            return response.read().decode("utf-8")
    except OSError as exc:
        fail(f"could not read OpenWrt downloads directory: {url}: {exc}")


def resolve_kmod_repository(base_url: str) -> str:
    kmods_url = urljoin(base_url, "kmods/")
    listing = read_listing(kmods_url)
    matches = list(
        dict.fromkeys(
            unescape(value)
            for value in re.findall(r'href="([0-9][^"/]+/)"', listing)
        )
    )
    if len(matches) != 1:
        fail(f"expected one exact kernel-module repository, found {len(matches)}")
    return urljoin(kmods_url, matches[0])


def resolve_kmod_package(kmods_url: str, package: str) -> str:
    listing = read_listing(kmods_url)
    pattern = rf'href="({re.escape(package)}-\d+\.\d+\.\d+-[^"]+\.apk)"'
    matches = list(dict.fromkeys(unescape(value) for value in re.findall(pattern, listing)))
    if len(matches) != 1:
        fail(f"expected one {package} package in {kmods_url}, found {len(matches)}")
    return urljoin(kmods_url, matches[0])


def main() -> None:
    if len(sys.argv) != 4:
        fail("usage: resolve-openwrt-artifacts.py <release> <target> <subtarget>")

    release = sys.argv[1]
    if release.startswith("v"):
        release = release[1:]
    if release != "snapshot" and not re.fullmatch(r"\d+\.\d+\.\d+", release):
        fail("version must be an exact final release such as 25.12.5 or snapshot")

    target, subtarget = sys.argv[2], sys.argv[3]
    if release == "snapshot":
        base_url = f"{OPENWRT_DOWNLOADS}/snapshots/targets/{target}/{subtarget}/"
    else:
        base_url = f"{OPENWRT_DOWNLOADS}/releases/{release}/targets/{target}/{subtarget}/"
    kmods_url = resolve_kmod_repository(base_url)
    result = {
        "release": release,
        "target": target,
        "subtarget": subtarget,
        "base_url": base_url,
        "sdk_url": resolve_artifact(base_url, release, target, subtarget, "sdk"),
        "imagebuilder_url": resolve_artifact(base_url, release, target, subtarget, "imagebuilder"),
        "feeds_buildinfo_url": urljoin(base_url, "feeds.buildinfo"),
        "version_buildinfo_url": urljoin(base_url, "version.buildinfo"),
        "kmods_url": kmods_url,
        # OpenWrt publishes kmod checksums in the target-level manifest. The
        # kmods directory itself contains index.json and APKs, but no nested
        # sha256sums file.
        "kmods_sha256sums_url": urljoin(base_url, "sha256sums"),
        "kmod_bluetooth_url": resolve_kmod_package(kmods_url, "kmod-bluetooth"),
        "kmod_btmtk_url": resolve_kmod_package(kmods_url, "kmod-btmtk"),
        "kmod_btusb_url": resolve_kmod_package(kmods_url, "kmod-btusb"),
        "kmod_sound_core_url": resolve_kmod_package(kmods_url, "kmod-sound-core"),
        "kmod_usb_audio_url": resolve_kmod_package(kmods_url, "kmod-usb-audio"),
    }
    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
