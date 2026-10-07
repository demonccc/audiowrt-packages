#!/usr/bin/env python3
"""Materialize only selected paths from an exact OpenWrt feed source.

This is source material for AudioWRT package builds, not an enabled OpenWrt feed:
the checkout is sparse and is never passed to scripts/feeds update/install.
"""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

FEED_RE = re.compile(
    r"^\s*src-git(?:-full)?"
    r"(?P<flags>(?:\s+--[A-Za-z0-9_-]+(?:=\S+)?)*)"
    r"\s+(?P<name>\S+)\s+(?P<source>\S+)\s*$"
)


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def run(*args: str, cwd: Path | None = None) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def read_feed_source(topdir: Path, feed: str) -> str:
    config = topdir / "feeds.conf.default"
    if not config.is_file():
        fail(f"OpenWrt feeds.conf.default is missing under {topdir}")
    for raw in config.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        match = FEED_RE.match(line)
        if match and match.group("name") == feed:
            return match.group("source")
    fail(f"feed {feed!r} not found in {config}")


def parse_source(source: str) -> tuple[str, str, str]:
    if "^" in source:
        url, commit = source.split("^", 1)
        return url, "commit", commit
    if ";" in source:
        url, branch = source.split(";", 1)
        return url, "branch", branch
    return source, "head", ""


def read_paths(path_file: Path, feed: str) -> list[str]:
    paths: list[str] = []
    for raw in path_file.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 1)
        if len(parts) != 2:
            fail(f"invalid source-path entry: {raw}")
        entry_feed, source_path = parts
        if entry_feed == feed:
            paths.append(source_path)
    if not paths:
        fail(f"no source paths configured for feed {feed}")
    return sorted(set(paths))


def ensure_sparse_checkout(target: Path, source: str, sparse_paths: list[str]) -> None:
    url, mode, ref = parse_source(source)
    signature = hashlib.sha256(
        (source + "\n" + "\n".join(sparse_paths) + "\n").encode("utf-8")
    ).hexdigest()
    stamp = target / ".audiowrt-source-signature"

    if (target / ".git").is_dir() and stamp.is_file():
        if stamp.read_text(encoding="utf-8").strip() == signature:
            return

    if target.exists():
        shutil.rmtree(target)
    target.parent.mkdir(parents=True, exist_ok=True)

    run("git", "clone", "--filter=blob:none", "--no-checkout", url, str(target))
    run("git", "sparse-checkout", "init", "--cone", cwd=target)
    run("git", "sparse-checkout", "set", *sparse_paths, cwd=target)

    if mode == "commit":
        run("git", "fetch", "--depth=1", "origin", ref, cwd=target)
        run("git", "-c", "advice.detachedHead=false", "checkout", "--detach", "FETCH_HEAD", cwd=target)
    elif mode == "branch":
        run("git", "fetch", "--depth=1", "origin", ref, cwd=target)
        run("git", "-c", "advice.detachedHead=false", "checkout", "--detach", "FETCH_HEAD", cwd=target)
    else:
        run("git", "fetch", "--depth=1", "origin", "HEAD", cwd=target)
        run("git", "-c", "advice.detachedHead=false", "checkout", "--detach", "FETCH_HEAD", cwd=target)

    stamp.write_text(signature + "\n", encoding="utf-8")


def ensure_source_link(topdir: Path, feed: str, target: Path) -> None:
    link = topdir / "feeds" / feed
    link.parent.mkdir(parents=True, exist_ok=True)
    if link.is_symlink():
        if link.resolve() == target.resolve():
            return
        link.unlink()
    elif link.exists():
        shutil.rmtree(link)
    link.symlink_to(target)


def main() -> int:
    if len(sys.argv) != 5:
        print(
            "usage: materialize-openwrt-feed-source.py "
            "<openwrt-topdir> <feed> <cache-dir> <source-paths-file>",
            file=sys.stderr,
        )
        return 2

    topdir = Path(sys.argv[1]).resolve()
    feed = sys.argv[2]
    cache_root = Path(sys.argv[3]).resolve()
    source_paths_file = Path(sys.argv[4]).resolve()

    source = read_feed_source(topdir, feed)
    sparse_paths = read_paths(source_paths_file, feed)
    target = cache_root / feed

    ensure_sparse_checkout(target, source, sparse_paths)
    ensure_source_link(topdir, feed, target)
    print(f"Materialized {feed} source paths only: {', '.join(sparse_paths)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
