#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import re
import sys
from pathlib import Path


TOOLCHAIN_PROVIDED = {
    "libc",
    "libgcc",
    "libpthread",
    "librt",
}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def load_owned_packages(path: Path) -> set[str]:
    packages: set[str] = set()
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 1)
        if len(parts) != 2 or not all(parts):
            fail(f"invalid package-build-targets entry on line {number}")
        package = parts[0]
        if package in packages:
            fail(f"duplicate package-build-targets entry: {package}")
        packages.add(package)
    return packages


def normalize_dependency(token: str) -> str:
    token = token.strip()
    if not token or token.startswith("@"):
        return ""
    token = token.lstrip("+")
    if ":" in token:
        token = token.rsplit(":", 1)[1]
    token = token.lstrip("+")
    token = re.split(r"[<>= ]", token, maxsplit=1)[0]
    token = token.split("/", 1)[0]
    # Kernel packages are runtime requirements, not headers or libraries that
    # an AudioWRT userspace source package needs staged for compilation.
    if token.startswith("kmod-") or token == "kernel":
        return ""
    return token


def load_metadata(path: Path):
    metadata: dict[str, dict[str, list[str]]] = {}
    source_fields: dict[str, list[str]] = {}
    current: str | None = None

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if raw.startswith("Build-Depends:"):
            source_fields["build"] = raw.split(":", 1)[1].strip().split()
            continue
        if raw.startswith("Build-Depends/host:"):
            source_fields["host"] = raw.split(":", 1)[1].strip().split()
            continue
        if raw.startswith("Package:"):
            current = raw.split(":", 1)[1].strip()
            metadata[current] = {
                "build": list(source_fields.get("build", [])),
                "host": list(source_fields.get("host", [])),
                "runtime": [],
                "provides": [],
            }
            source_fields = {}
            continue
        if current and raw.startswith("Depends:"):
            metadata[current]["runtime"] = raw.split(":", 1)[1].strip().split()
        if current and raw.startswith("Provides:"):
            metadata[current]["provides"] = raw.split(":", 1)[1].strip().split()

    return metadata


def main() -> None:
    if len(sys.argv) < 4:
        fail(
            "usage: resolve-source-build-dependencies.py "
            "<package-build-targets> <packageinfo> "
            "<source-package> [<source-package> ...] "
            "[--providers <selected-package> ...]"
        )

    targets_path = Path(sys.argv[1])
    packageinfo_path = Path(sys.argv[2])
    args = sys.argv[3:]
    if "--providers" in args:
        split = args.index("--providers")
        selected = args[:split]
        providers = args[split + 1 :]
    else:
        selected = args
        providers = list(selected)

    if not selected:
        fail("at least one source package is required")

    if not targets_path.is_file():
        fail(f"package build target map not found: {targets_path}")
    if not packageinfo_path.is_file():
        fail(f"OpenWrt package metadata not found: {packageinfo_path}")

    owned = load_owned_packages(targets_path)
    metadata = load_metadata(packageinfo_path)
    selected_provides = {
        normalize_dependency(provided)
        for package in providers
        for provided in metadata.get(package, {}).get("provides", [])
    }
    dependencies: list[str] = []
    seen: set[str] = set()

    for package in selected:
        if package not in metadata:
            fail(f"source package metadata not found: {package}")
        fields = metadata[package]
        for field in ("build", "host", "runtime"):
            for token in fields[field]:
                dependency = normalize_dependency(token)
                if not dependency:
                    continue
                if dependency in owned or dependency in selected_provides or dependency in TOOLCHAIN_PROVIDED:
                    continue
                if dependency not in seen:
                    seen.add(dependency)
                    dependencies.append(dependency)

    for dependency in dependencies:
        print(dependency)


if __name__ == "__main__":
    main()
