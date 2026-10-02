#!/usr/bin/env python3
"""Create immutable metadata for one incremental AudioWRT package build."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

PACKAGE_RE = re.compile(r"^define Package/([^\s]+)", re.MULTILINE)
KERNEL_RE = re.compile(r"^define KernelPackage/([^\s]+)", re.MULTILINE)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_map(repo: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for root in ("audiowrt", "ported", "trimmed", "tailored"):
        base = repo / root
        if not base.is_dir():
            continue
        for makefile in base.glob("*/Makefile"):
            text = makefile.read_text(encoding="utf-8", errors="replace")
            rel = makefile.parent.relative_to(repo).as_posix()
            for name in PACKAGE_RE.findall(text):
                result[name] = rel
            for name in KERNEL_RE.findall(text):
                result[f"kmod-{name}"] = rel
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--packages-dir", required=True)
    parser.add_argument("--context", required=True)
    parser.add_argument("--scope", choices=("all", "arch", "kernel"), required=True)
    parser.add_argument("--channel", choices=("stable", "testing"), required=True)
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--repository", required=True, help="owner/repo")
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    repo = Path.cwd().resolve()
    packages_dir = Path(args.packages_dir)
    context = json.loads(Path(args.context).read_text(encoding="utf-8"))
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
        "schema": 2,
        "channel": args.channel,
        "scope": args.scope,
        "openwrt_version": context["openwrt_version"],
        "target": context["target"],
        "subtarget": context["subtarget"],
        "architecture": context["arch"],
        "source_commit": args.source_commit,
        "release_tag": args.release_tag,
        "packages": packages,
        "remove": [],
    }
    Path(args.output).write_text(json.dumps(update, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
