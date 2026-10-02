#!/usr/bin/env python3
"""Rebuild the complete GitHub Pages package index from immutable release updates."""
from __future__ import annotations

import argparse
import json
import os
import urllib.request
from collections import defaultdict
from pathlib import Path

API = "https://api.github.com"


def request_json(url: str, token: str):
    request = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "AudioWRT-package-index",
    })
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def request_bytes(url: str, token: str) -> bytes:
    request = urllib.request.Request(url, headers={
        "Accept": "application/octet-stream",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "AudioWRT-package-index",
    })
    with urllib.request.urlopen(request) as response:
        return response.read()


def iter_releases(repository: str, token: str):
    page = 1
    while True:
        releases = request_json(f"{API}/repos/{repository}/releases?per_page=100&page={page}", token)
        if not releases:
            return
        yield from releases
        if len(releases) < 100:
            return
        page += 1


def state_key(update: dict) -> tuple[str, str, str, str, str]:
    scope = update.get("scope")
    if not scope:  # schema 1 compatibility
        scope = "kernel"
    if scope == "all":
        return (update["channel"], update["openwrt_version"], "all", "", "")
    if scope == "arch":
        return (update["channel"], update["openwrt_version"], "arch", update["architecture"], "")
    return (update["channel"], update["openwrt_version"], "kernel", update["target"], update["subtarget"])


def repository_path(output: Path, key: tuple[str, str, str, str, str]) -> Path:
    channel, version, scope, first, second = key
    if scope == "all":
        return output / channel / version / "all" / "repository.json"
    if scope == "arch":
        return output / channel / version / "packages" / first / "repository.json"
    return output / channel / version / "targets" / first / second / "repository.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        raise SystemExit("ERROR: GITHUB_TOKEN is required")

    updates = []
    for release in iter_releases(args.repository, token):
        asset = next((a for a in release.get("assets", []) if a["name"] == "repository-update.json"), None)
        if not asset:
            continue
        update = json.loads(request_bytes(asset["url"], token).decode("utf-8"))
        update["published_at"] = release.get("published_at") or release.get("created_at") or ""
        updates.append(update)

    updates.sort(key=lambda item: (item.get("published_at", ""), item.get("release_tag", "")))
    state: dict[tuple[str, str, str, str, str], dict] = {}
    revisions = defaultdict(int)

    for update in updates:
        key = state_key(update)
        revisions[key] += 1
        scope = key[2]
        current = state.setdefault(key, {
            "schema": 2,
            "channel": update["channel"],
            "scope": scope,
            "openwrt_version": update["openwrt_version"],
            "target": update.get("target", ""),
            "subtarget": update.get("subtarget", ""),
            "architecture": update.get("architecture", "all"),
            "revision": 0,
            "last_release_tag": "",
            "packages": {},
        })
        for name in update.get("remove", []):
            current["packages"].pop(name, None)
        current["packages"].update(update.get("packages", {}))
        current["revision"] = revisions[key]
        current["last_release_tag"] = update["release_tag"]

    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    catalog = []
    for key, repository in sorted(state.items()):
        path = repository_path(output, key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(repository, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        catalog.append({
            "channel": repository["channel"],
            "openwrt_version": repository["openwrt_version"],
            "scope": repository["scope"],
            "target": repository["target"],
            "subtarget": repository["subtarget"],
            "architecture": repository["architecture"],
            "revision": repository["revision"],
            "path": path.relative_to(output).as_posix(),
        })

    (output / "index.json").write_text(
        json.dumps({"schema": 2, "repositories": catalog}, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
