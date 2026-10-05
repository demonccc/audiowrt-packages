#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def load_targets(path: Path):
    targets = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 1)
        if len(parts) != 2 or not all(parts):
            fail(f"invalid package-build-targets entry on line {number}")
        package, target = parts
        if package in targets:
            fail(f"duplicate package-build-targets entry: {package}")
        targets[package] = target
    return targets


def normalize_dependency(token: str) -> str:
    token = token.strip().lstrip("+@")
    if not token or token.startswith("$(") or token.startswith("("):
        return ""
    if ":" in token:
        token = token.rsplit(":", 1)[1]
    token = token.lstrip("+@")
    return re.split(r"[<>= ()]", token, maxsplit=1)[0]


def load_package_metadata(path: Path):
    dependencies = {}
    provides = {}
    current = None
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if raw.startswith("Package:"):
            current = raw.split(":", 1)[1].strip()
            dependencies.setdefault(current, [])
            provides.setdefault(current, [])
            continue
        if current and raw.startswith("Depends:"):
            value = raw.split(":", 1)[1].strip()
            for token in value.split():
                dependency = normalize_dependency(token)
                if dependency and dependency not in dependencies[current]:
                    dependencies[current].append(dependency)
            continue
        if current and raw.startswith("Provides:"):
            value = raw.split(":", 1)[1].strip()
            for token in value.split():
                capability = normalize_dependency(token)
                if capability and capability not in provides[current]:
                    provides[current].append(capability)
    return dependencies, provides


def logical_make_lines(text: str):
    pending = ""
    for raw in text.splitlines():
        line = raw.rstrip()
        if pending:
            line = pending + line.lstrip()
        if line.endswith("\\"):
            pending = line[:-1] + " "
            continue
        yield line
        pending = ""
    if pending:
        yield pending


def load_extra_dependencies(repo_root: Path, owned_packages: set[str]):
    """Return AudioWRT runtime edges hidden from tmp/.packageinfo.

    OpenWrt EXTRA_DEPENDS is deliberately packaging-only: it is written into the
    resulting package metadata but does not participate in the normal build
    dependency graph. AudioWRT uses it for trimmed runtime providers so source
    builds can compile against official development packages without rebuilding
    those providers transitively. Package CI still needs those AudioWRT runtime
    providers built first so OpenWrt's shared-library checker can resolve them.
    """
    package_makefiles = {}
    for category in ("audiowrt", "ported", "trimmed", "tailored"):
        root = repo_root / category
        if not root.is_dir():
            continue
        for makefile in root.glob("*/Makefile"):
            text = makefile.read_text(encoding="utf-8", errors="replace")
            for match in re.finditer(r"^define (?:Package|KernelPackage)/([^\s]+)", text, re.M):
                name = match.group(1)
                if match.group(0).startswith("define KernelPackage/"):
                    name = "kmod-" + name
                package_makefiles.setdefault(name, makefile)

    extra_dependencies = {package: [] for package in owned_packages}
    for package in owned_packages:
        makefile = package_makefiles.get(package)
        if makefile is None:
            continue
        for line in logical_make_lines(makefile.read_text(encoding="utf-8", errors="replace")):
            match = re.match(r"\s*EXTRA_DEPENDS\s*(?::|\+)?=\s*(.*)$", line)
            if not match:
                continue
            for token in match.group(1).split():
                dependency = normalize_dependency(token)
                if (
                    dependency
                    and dependency in owned_packages
                    and dependency not in extra_dependencies[package]
                ):
                    extra_dependencies[package].append(dependency)
    return extra_dependencies


def main() -> None:
    if len(sys.argv) < 4:
        fail(
            "usage: resolve-package-build-targets.py "
            "<package-build-targets> <packageinfo> <root> [<root> ...] "
            "[--providers <package> ...]"
        )

    targets_path = Path(sys.argv[1]).resolve()
    packageinfo_path = Path(sys.argv[2])
    arguments = sys.argv[3:]
    providers = []
    if "--providers" in arguments:
        index = arguments.index("--providers")
        roots = arguments[:index]
        providers = arguments[index + 1 :]
    else:
        roots = arguments
    if not roots:
        fail("at least one package root is required")

    if not targets_path.is_file():
        fail(f"package build target map not found: {targets_path}")
    if not packageinfo_path.is_file():
        fail(f"OpenWrt package metadata not found: {packageinfo_path}")

    targets = load_targets(targets_path)
    dependencies, package_provides = load_package_metadata(packageinfo_path)
    repo_root = targets_path.parents[2]
    extra_dependencies = load_extra_dependencies(repo_root, set(targets))
    selected = []
    state = {}

    selected_providers = {}
    for provider in providers:
        if provider not in targets:
            continue
        for capability in package_provides.get(provider, []):
            selected_providers.setdefault(capability, []).append(provider)

    def visit(package: str, chain):
        if package not in targets:
            return
        marker = state.get(package, 0)
        if marker == 2:
            return
        if marker == 1:
            fail("AudioWRT package dependency cycle: " + " -> ".join([*chain, package]))

        state[package] = 1
        package_dependencies = [
            *dependencies.get(package, []),
            *extra_dependencies.get(package, []),
        ]
        seen_dependencies = set()
        for dependency in package_dependencies:
            if dependency in seen_dependencies:
                continue
            seen_dependencies.add(dependency)
            if dependency in targets:
                visit(dependency, [*chain, package])
                continue
            matching_providers = selected_providers.get(dependency, [])
            if len(matching_providers) > 1:
                fail(
                    f"multiple selected AudioWRT providers for {dependency}: "
                    + ", ".join(sorted(matching_providers))
                )
            if matching_providers:
                visit(matching_providers[0], [*chain, package])
        state[package] = 2
        selected.append(package)

    for root in roots:
        visit(root, [])

    if not selected:
        fail("none of the requested packages are AudioWRT-owned build roots")

    for package in selected:
        print(f"{package}|{targets[package]}")


if __name__ == "__main__":
    main()
