#!/usr/bin/env python3
"""Materialize the SDK-pinned OpenWrt base source without indexing/installing it.

Derived AudioWRT packages need the canonical OpenWrt recipe while the AudioWRT
feed itself is being scanned. Calling `scripts/feeds update base` from a package
Makefile is recursive and unsafe, so this helper performs only the source checkout
specified by the selected SDK's feeds.conf and creates the same feeds/base link.
It never creates feed metadata, installs packages, or invokes make.
"""

from __future__ import annotations

import fcntl
import re
import shutil
import subprocess
import sys
from pathlib import Path

BASE_RE = re.compile(
    r"^\s*src-git(?:-full)?"
    r"(?P<flags>(?:\s+--[A-Za-z0-9_-]+(?:=\S+)?)*)"
    r"\s+base\s+(?P<source>\S+)\s*$"
)
ROOT_RE = re.compile(r"(?:^|\s)--root=(\S+)(?:\s|$)")


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def run(*args: str, cwd: Path | None = None) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def read_base_source(topdir: Path) -> tuple[str, str]:
    config = topdir / "feeds.conf"
    if not config.is_file():
        config = topdir / "feeds.conf.default"
    if not config.is_file():
        fail(f"OpenWrt feed configuration is missing under {topdir}")

    for raw in config.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        match = BASE_RE.match(line)
        if not match:
            continue
        root_match = ROOT_RE.search(match.group("flags") or "")
        root = root_match.group(1) if root_match else ""
        if root != "package":
            fail(
                "OpenWrt base feed must use --root=package for AudioWRT derived "
                f"packages, found root={root!r}"
            )
        return match.group("source"), root

    fail(f"OpenWrt base src-git feed not found in {config}")


def parse_source(source: str) -> tuple[str, str, str]:
    if "^" in source:
        url, commit = source.split("^", 1)
        if not url or not commit:
            fail(f"invalid commit-pinned base feed source: {source}")
        return url, "commit", commit
    if ";" in source:
        url, branch = source.split(";", 1)
        if not url or not branch:
            fail(f"invalid branch-pinned base feed source: {source}")
        return url, "branch", branch
    return source, "head", ""


def ensure_checkout(target: Path, source: str) -> None:
    url, mode, ref = parse_source(source)
    stamp = target / ".audiowrt-source"
    expected = f"source={source}\n"

    if (target / ".git").is_dir() and stamp.is_file():
        if stamp.read_text(encoding="utf-8") == expected:
            return

    if target.exists() and not (target / ".git").is_dir():
        shutil.rmtree(target)

    if not (target / ".git").is_dir():
        target.parent.mkdir(parents=True, exist_ok=True)
        if mode == "branch":
            run("git", "clone", "--filter=blob:none", "--depth=1", "--branch", ref, url, str(target))
        else:
            run("git", "clone", "--filter=blob:none", "--no-checkout", url, str(target))

    if mode == "commit":
        # A --no-checkout clone can have HEAD pointing at the requested commit
        # while the worktree is still empty. Always populate the worktree. Fetch
        # only when the requested object is not already available locally.
        present = subprocess.run(
            ["git", "cat-file", "-e", f"{ref}^{{commit}}"],
            cwd=target,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if present.returncode != 0:
            run("git", "fetch", "--depth=1", "origin", ref, cwd=target)
        run("git", "-c", "advice.detachedHead=false", "checkout", "--detach", ref, cwd=target)
    elif mode == "branch":
        run("git", "fetch", "--depth=1", "origin", ref, cwd=target)
        run("git", "-c", "advice.detachedHead=false", "checkout", "--detach", "FETCH_HEAD", cwd=target)
    else:
        run("git", "fetch", "--depth=1", "origin", "HEAD", cwd=target)
        run("git", "-c", "advice.detachedHead=false", "checkout", "--detach", "FETCH_HEAD", cwd=target)

    stamp.write_text(expected, encoding="utf-8")


def ensure_link(topdir: Path, root: str) -> None:
    link = topdir / "feeds" / "base"
    expected = Path("base_root") / root
    if link.is_symlink():
        if Path(link.readlink()) == expected:
            return
        link.unlink()
    elif link.exists():
        fail(f"refusing to replace non-symlink OpenWrt base feed path: {link}")
    link.symlink_to(expected)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: materialize-openwrt-base.py <openwrt-topdir>", file=sys.stderr)
        return 2

    topdir = Path(sys.argv[1]).resolve()
    feeds_dir = topdir / "feeds"
    feeds_dir.mkdir(parents=True, exist_ok=True)

    # Feed scanning may evaluate several derived Makefiles concurrently. One
    # process owns the checkout while the others wait and then reuse it.
    lock_path = feeds_dir / ".audiowrt-base-materialize.lock"
    with lock_path.open("w", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        source, root = read_base_source(topdir)
        target = feeds_dir / "base_root"
        ensure_checkout(target, source)
        canonical_root = target / root
        if not canonical_root.is_dir():
            fail(f"materialized OpenWrt base root is missing: {canonical_root}")
        ensure_link(topdir, root)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
