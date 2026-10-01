#!/usr/bin/env python3
"""Create immutable metadata for one incremental AudioWRT package build."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

PACKAGE_RE = re.compile(r"^define Package/([^\s]+)", re.MULTILINE)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_map(repo: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for makefile in repo.rglob("Makefile"):
        if ".git" in makefile.parts:
            continue
        text = makefile.read_text(encoding="utf-8", errors="replace")
        for name in PACKAGE_RE.findall(text):
            result[name] = makefile.parent.relative_to(repo).as_posix()
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--packages-dir", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--channel", choices=("stable", "testing"), required=True)
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--repository", required=True, help="owner/repo")
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    repo = Path.cwd().resolve()
    packages_dir = Path(args.packages_dir)
    platform = json.loads(Path(args.platform).read_text(encoding="utf-8"))
    profile = json.loads(Path(args.profile).read_text(encoding="utf-8"))
    sources = source_map(repo)

    names = sorted(sources, key=len, reverse=True)
    packages: dict[str, dict[str, str]] = {}
    for apk in sorted(packages_dir.glob("*.apk")):
        stem = apk.name[:-4]
        name = next((candidate for candidate in names if stem.startswith(candidate + "-")), None)
        if not name:
            raise SystemExit(f"ERROR: cannot map APK filename to AudioWRT package: {apk.name}")
        version = stem[len(name) + 1 :]
        packages[name] = {
            "version": version,
            "filename": apk.name,
            "sha256": sha256(apk),
            "url": f"https://github.com/{args.repository}/releases/download/{args.release_tag}/{apk.name}",
            "release_tag": args.release_tag,
            "source_commit": args.source_commit,
            "source_dir": sources[name],
        }

    if not packages:
        raise SystemExit("ERROR: no APKs found for repository update")

    update = {
        "schema": 1,
        "channel": args.channel,
        "openwrt_version": profile["openwrt_version"],
        "openwrt_source": profile["openwrt_source"],
        "target": platform["target"],
        "subtarget": platform["subtarget"],
        "architecture": platform["arch_packages"],
        "source_commit": args.source_commit,
        "release_tag": args.release_tag,
        "packages": packages,
        "remove": [],
    }
    Path(args.output).write_text(json.dumps(update, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
