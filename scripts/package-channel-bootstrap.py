#!/usr/bin/env python3
"""Check whether every required package-build context exists in a channel.

The immutable GitHub Release history is the authoritative publication history.
A channel is bootstrapped only after each required profile has at least one
repository-update release. This also makes a partially failed first build retry
as a full bootstrap instead of silently becoming incremental.
"""
from __future__ import annotations

import argparse
import json
import urllib.request


DEFAULT_PROFILES = (
    "tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5",
    "linksys-ea8300-usb-bluetooth-audio-25.12.5",
    "raspberry-pi-3-usb-bluetooth-audio-25.12.5",
    "raspberry-pi-4-usb-bluetooth-audio-25.12.5",
    "x86-64-usb-bluetooth-audio-25.12.5",
)


def release_tags(repository: str, token: str) -> set[str]:
    tags: set[str] = set()
    page = 1
    while True:
        request = urllib.request.Request(
            f"https://api.github.com/repos/{repository}/releases?per_page=100&page={page}",
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {token}",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "audiowrt-package-bootstrap",
            },
        )
        with urllib.request.urlopen(request) as response:
            releases = json.load(response)
        if not releases:
            break
        tags.update(str(item.get("tag_name", "")) for item in releases)
        if len(releases) < 100:
            break
        page += 1
    return tags


def has_profile_release(tags: set[str], channel: str, profile: str) -> bool:
    prefix = f"packages-{channel}-"
    marker = f"-{profile}-"
    return any(tag.startswith(prefix) and marker in tag for tag in tags)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--channel", required=True, choices=("stable", "testing"))
    parser.add_argument("--token", required=True)
    parser.add_argument("--profile", action="append", dest="profiles")
    args = parser.parse_args()

    profiles = tuple(args.profiles or DEFAULT_PROFILES)
    tags = release_tags(args.repository, args.token)
    missing = [profile for profile in profiles if not has_profile_release(tags, args.channel, profile)]

    if missing:
        print("bootstrap_required=true")
        print("missing_profiles=" + " ".join(missing))
    else:
        print("bootstrap_required=false")
        print("missing_profiles=")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
