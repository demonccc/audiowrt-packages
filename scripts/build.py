#!/usr/bin/env python3
"""Profile-free package build entry point, usable locally and in CI.

Host mode enters the canonical openwrt-builder container; container mode
selects an SDK context and invokes this repository's package compilation stage.
No AudioWRT firmware checkout or firmware profile is involved.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tomllib

ROOT = Path(__file__).resolve().parents[1]
IMAGE = "demonccc/openwrt-builder:latest"
ROOTS = ("audiowrt", "ported", "trimmed", "tailored")


def packages() -> dict[str, Path]:
    found = {}
    for category in ROOTS:
        for item in sorted((ROOT / category).glob("*/Makefile")):
            found[item.parent.name] = item
    return found


def contexts(release: str, arch: str) -> list[tuple[str, str]]:
    data = tomllib.loads((ROOT / "repository/build-matrix.toml").read_text())
    architectures = data["architectures"]
    effective_arch = "x86_64" if arch == "all" else arch
    if effective_arch not in architectures:
        raise ValueError(f"Unknown architecture {arch}. Available: {', '.join(sorted(architectures))}, all")
    versions = architectures[effective_arch].get("versions", {})
    if release not in versions:
        raise ValueError(f"OpenWrt {release} not available for {arch}. Available: {', '.join(versions)}")
    cfg = versions[release]
    primary = cfg["sdk_target"]
    targets = [primary]
    if arch != "all":
        targets += cfg.get("kernel_targets", [])
    return [tuple(target.split("/", 1)) for target in dict.fromkeys(targets)]


def main() -> int:
    parser = argparse.ArgumentParser(description="Build AudioWRT package APKs (no firmware profiles)")
    parser.add_argument("command", choices=("build", "list"))
    parser.add_argument("--release", default="25.12.5")
    parser.add_argument("--arch", default="mips_24kc")
    parser.add_argument("--package", action="append", default=[], help="Package name(s), comma-separated or 'all'")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--output", default="output/local")
    parser.add_argument("--cache-dir", default=".cache/audiowrt-packages")
    parser.add_argument("--target", help="Optional specific SDK target")
    parser.add_argument("--subtarget", help="Optional specific SDK subtarget")
    parser.add_argument("--inside-container", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    available = packages()
    if args.command == "list":
        print("\n".join(sorted(available)))
        return 0
    selected = [name.strip() for entry in args.package for name in entry.replace(",", " ").split()]
    if not selected or "all" in selected:
        if selected and selected != ["all"]:
            parser.error("'all' cannot be combined with named packages")
        selected = sorted(available)
    unknown = set(selected) - available.keys()
    if unknown:
        parser.error("Unknown package(s): " + ", ".join(sorted(unknown)))
    if args.jobs < 1:
        parser.error("--jobs must be >= 1")
    selected = list(dict.fromkeys(selected))
    try:
        sdk_contexts = contexts(args.release, args.arch)
    except ValueError as error:
        parser.error(str(error))
    if args.target or args.subtarget:
        if not args.target or not args.subtarget:
            parser.error("--target and --subtarget must be supplied together")
        sdk_contexts = [(args.target, args.subtarget)]
    output = (ROOT / args.output).resolve()
    cache = (ROOT / args.cache_dir).resolve()
    for path in (output, cache):
        if not path.is_relative_to(ROOT):
            parser.error("Output and cache must be inside the repository checkout")
    if output == cache or cache.is_relative_to(output) or output.is_relative_to(cache):
        parser.error("Output and cache directories must be separate")
    if not args.inside_container:
        docker_args = [
            "docker", "run", "--rm",
            "-e", "HOME=/tmp",
            "-v", f"{ROOT}:/workspace",
            "-w", "/workspace",
        ]
        if hasattr(os, "getuid"):
            docker_args += ["--user", f"{os.getuid()}:{os.getgid()}"]
        docker_args += [IMAGE, "python3", "scripts/build.py", "build",
                        "--inside-container", "--release", args.release, "--arch", args.arch,
                        "--jobs", str(args.jobs), "--output", str(output.relative_to(ROOT)),
                        "--cache-dir", str(cache.relative_to(ROOT))]
        for pkg in selected:
            docker_args.extend(["--package", pkg])
        if args.target:
            docker_args.extend(["--target", args.target, "--subtarget", args.subtarget])
        print("Running package build in", IMAGE, flush=True)
        return subprocess.call(docker_args, cwd=ROOT)
    # Preserve existing source-category / scope detection.
    tasks = []
    for target, subtarget in sdk_contexts:
        for pkg in selected:
            source = available[pkg].read_text()
            scope = "kernel" if "define KernelPackage/" in source else (
                "all" if any(line.strip().replace(" ", "") in ("PKGARCH:=all", "PKGARCH=all")
                             for line in source.splitlines()) else "arch")
            if args.arch == "all" and scope != "all":
                continue
            tasks.append({"package": pkg, "scope": scope, "target": target, "subtarget": subtarget})
    if not tasks:
        parser.error("No matching package tasks for selected architecture")
    output.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    print(f"Building {len(tasks)} package task(s) using {len(sdk_contexts)} SDK context(s)", flush=True)
    failures = 0
    for target, subtarget in sdk_contexts:
        current = [sys.executable, "scripts/build-sdk.py",
                   "--release", args.release, "--arch", args.arch,
                   "--target", target, "--subtarget", subtarget,
                   "--output", str(output), "--jobs", str(args.jobs),
                   "--cache-dir", str(cache)]
        for task in tasks:
            if task["target"] == target and task["subtarget"] == subtarget:
                current.extend(["--package", task["package"]])
        failures |= subprocess.call(current, cwd=ROOT)
    return 1 if failures else 0

if __name__ == "__main__":
    sys.exit(main())
