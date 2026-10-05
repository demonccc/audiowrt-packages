#!/usr/bin/env python3
"""Promote exact testing APKs selected by production-packages.yaml to stable."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import yaml

API = "https://api.github.com"
UPLOADS = "https://uploads.github.com"


def api_request(url: str, token: str, *, method: str = "GET", data: bytes | None = None,
                content_type: str = "application/vnd.github+json"):
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "AudioWRT-production-promotion",
        "Content-Type": content_type,
    })
    with urllib.request.urlopen(req) as response:
        body = response.read()
        if not body:
            return None
        if "json" in response.headers.get("Content-Type", ""):
            return json.loads(body)
        return body


def releases(repository: str, token: str) -> list[dict]:
    result = []
    page = 1
    while True:
        batch = api_request(f"{API}/repos/{repository}/releases?per_page=100&page={page}", token)
        if not batch:
            break
        result.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return result


def asset_bytes(asset: dict, token: str) -> bytes:
    req = urllib.request.Request(asset["url"], headers={
        "Accept": "application/octet-stream",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "AudioWRT-production-promotion",
    })
    with urllib.request.urlopen(req) as response:
        return response.read()


def update_for_release(release: dict, token: str) -> dict | None:
    asset = next((a for a in release.get("assets", []) if a["name"] == "repository-update.json"), None)
    if not asset:
        return None
    update = json.loads(asset_bytes(asset, token).decode("utf-8"))
    update["_release"] = release
    update["_published_at"] = release.get("published_at") or release.get("created_at") or ""
    return update


def validate_manifest(data: object) -> list[dict]:
    if not isinstance(data, dict):
        raise ValueError("manifest root must be a mapping")
    allowed = {"all", "architectures", "targets"}
    unknown = set(data) - allowed
    if unknown:
        raise ValueError(f"unknown root key(s): {', '.join(sorted(unknown))}")

    desired: list[dict] = []

    def add_packages(scope: str, selector: str, packages: object) -> None:
        if packages is None:
            return
        if not isinstance(packages, dict):
            raise ValueError(f"{scope}/{selector or '-'} must be a mapping of packages")
        for package, entries in packages.items():
            if not isinstance(package, str) or not package:
                raise ValueError("package names must be non-empty strings")
            if not isinstance(entries, list) or not entries:
                raise ValueError(f"{package} must contain a non-empty release list")
            for entry in entries:
                if not isinstance(entry, dict):
                    raise ValueError(f"{package} release entry must be a mapping")
                if set(entry) != {"release", "openwrt_versions"}:
                    raise ValueError(f"{package} entries must contain only release and openwrt_versions")
                release = entry["release"]
                versions = entry["openwrt_versions"]
                if not isinstance(release, str) or not release:
                    raise ValueError(f"{package} release must be a non-empty string")
                if not isinstance(versions, list) or not versions or not all(isinstance(v, str) and v for v in versions):
                    raise ValueError(f"{package} openwrt_versions must be a non-empty string list")
                for openwrt_version in versions:
                    desired.append({
                        "scope": scope,
                        "selector": selector,
                        "package": package,
                        "release": release,
                        "openwrt_version": openwrt_version,
                    })

    add_packages("all", "", data.get("all", {}))

    architectures = data.get("architectures", {})
    if not isinstance(architectures, dict):
        raise ValueError("architectures must be a mapping")
    for arch, packages in architectures.items():
        if not isinstance(arch, str) or not arch:
            raise ValueError("architecture names must be non-empty strings")
        add_packages("arch", arch, packages)

    targets = data.get("targets", {})
    if not isinstance(targets, dict):
        raise ValueError("targets must be a mapping")
    for target, packages in targets.items():
        if not isinstance(target, str) or target.count("/") != 1:
            raise ValueError(f"target must be target/subtarget: {target!r}")
        add_packages("kernel", target, packages)

    seen = set()
    for item in desired:
        key = tuple(item[k] for k in ("scope", "selector", "package", "release", "openwrt_version"))
        if key in seen:
            raise ValueError(f"duplicate production package entry: {key}")
        seen.add(key)
    return desired


def context_matches(update: dict, item: dict) -> bool:
    if update.get("channel") != "testing" or update.get("openwrt_version") != item["openwrt_version"]:
        return False
    if update.get("scope") != item["scope"]:
        return False
    if item["scope"] == "arch":
        return update.get("architecture") == item["selector"]
    if item["scope"] == "kernel":
        target, subtarget = item["selector"].split("/", 1)
        return update.get("target") == target and update.get("subtarget") == subtarget
    return True


def stable_key(update: dict, package: str) -> tuple:
    scope = update.get("scope")
    if scope == "all":
        selector = ""
    elif scope == "arch":
        selector = update.get("architecture", "")
    else:
        selector = f"{update.get('target','')}/{update.get('subtarget','')}"
    return (scope, selector, update.get("openwrt_version"), package)


def safe(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="repository/production-packages.yaml")
    parser.add_argument("--repository")
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()

    manifest = yaml.safe_load(Path(args.manifest).read_text(encoding="utf-8")) or {}
    desired = validate_manifest(manifest)
    print(f"Validated {len(desired)} production package selection(s)")
    if args.validate_only:
        return 0

    repository = args.repository or os.environ.get("GITHUB_REPOSITORY")
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not repository or not token:
        raise SystemExit("ERROR: repository and GITHUB_TOKEN are required")

    all_releases = releases(repository, token)
    updates = []
    for release in all_releases:
        update = update_for_release(release, token)
        if update:
            updates.append(update)

    testing_updates = sorted(
        (u for u in updates if u.get("channel") == "testing"),
        key=lambda u: u.get("_published_at", ""), reverse=True,
    )
    stable_updates = [u for u in updates if u.get("channel") == "stable"]
    existing_tags = {r["tag_name"] for r in all_releases}

    stable_current: dict[tuple, dict] = {}
    for update in sorted(stable_updates, key=lambda u: u.get("_published_at", "")):
        for package, meta in update.get("packages", {}).items():
            stable_current[stable_key(update, package)] = meta

    promoted = 0
    skipped = 0
    for item in desired:
        candidate = None
        meta = None
        for update in testing_updates:
            if not context_matches(update, item):
                continue
            package_meta = update.get("packages", {}).get(item["package"])
            if package_meta and package_meta.get("version") == item["release"]:
                candidate = update
                meta = package_meta
                break
        if not candidate or not meta:
            raise SystemExit(
                "ERROR: approved production artifact not found in testing: "
                f"{item['package']} {item['release']} / OpenWrt {item['openwrt_version']} / "
                f"{item['scope']} {item['selector']}"
            )

        key = (item["scope"], item["selector"], item["openwrt_version"], item["package"])
        current = stable_current.get(key)
        if current and current.get("version") == meta.get("version") and current.get("sha256") == meta.get("sha256"):
            print(f"Already stable: {item['package']} {item['release']} / {item['openwrt_version']} / {item['selector'] or 'all'}")
            skipped += 1
            continue

        testing_release = candidate["_release"]
        filename = meta["filename"]
        apk_asset = next((a for a in testing_release.get("assets", []) if a["name"] == filename), None)
        if not apk_asset:
            raise SystemExit(f"ERROR: testing APK asset missing: {testing_release['tag_name']} / {filename}")
        apk = asset_bytes(apk_asset, token)
        digest = hashlib.sha256(apk).hexdigest()
        if digest != meta.get("sha256"):
            raise SystemExit(f"ERROR: SHA256 mismatch while promoting {filename}")

        selector = item["selector"] or "all"
        tag = safe(f"packages-stable-{item['openwrt_version']}-{selector}-{item['package']}-{item['release']}-{digest[:12]}")
        if tag in existing_tags:
            raise SystemExit(f"ERROR: stable release tag already exists but is not current in repository state: {tag}")

        stable_update = {k: v for k, v in candidate.items() if not k.startswith("_")}
        stable_update["channel"] = "stable"
        stable_update["release_tag"] = tag
        stable_meta = dict(meta)
        stable_meta["release_tag"] = tag
        stable_meta["url"] = f"https://github.com/{repository}/releases/download/{tag}/{filename}"
        stable_update["packages"] = {item["package"]: stable_meta}
        stable_update["remove"] = []

        release_payload = json.dumps({
            "tag_name": tag,
            "target_commitish": candidate["source_commit"],
            "name": tag,
            "body": (
                f"Promoted from tested release {testing_release['tag_name']}\n\n"
                f"Artifact SHA256: {digest}"
            ),
            "draft": False,
            "prerelease": False,
        }).encode()
        created = api_request(f"{API}/repos/{repository}/releases", token, method="POST", data=release_payload)
        release_id = created["id"]

        def upload(name: str, body: bytes, content_type: str) -> None:
            quoted = urllib.parse.quote(name)
            api_request(
                f"{UPLOADS}/repos/{repository}/releases/{release_id}/assets?name={quoted}",
                token, method="POST", data=body, content_type=content_type,
            )

        upload(filename, apk, "application/vnd.android.package-archive")
        upload("repository-update.json", (json.dumps(stable_update, indent=2, sort_keys=True) + "\n").encode(), "application/json")
        print(f"Promoted: {item['package']} {item['release']} / {item['openwrt_version']} / {selector}")
        promoted += 1
        existing_tags.add(tag)
        stable_current[key] = stable_meta

    print(f"Production promotion complete: {promoted} promoted, {skipped} already stable")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
