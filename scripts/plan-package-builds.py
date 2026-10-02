#!/usr/bin/env python3
"""Create the minimal dynamic build matrix for changed AudioWRT packages."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import tomllib
from collections import deque
from pathlib import Path

PACKAGE_RE = re.compile(r"^define Package/([^\s]+)", re.MULTILINE)
KERNEL_RE = re.compile(r"^define KernelPackage/([^\s]+)", re.MULTILINE)
ALL_RE = re.compile(r"^\s*PKGARCH\s*:?=\s*all\s*$", re.MULTILINE)
PACKAGE_ROOTS = ("audiowrt", "ported", "trimmed", "tailored")
IGNORED_PREFIXES = ("docs/", ".github/")


def git_changed_files(base: str, head: str) -> list[str]:
    out = subprocess.check_output(["git", "diff", "--name-only", f"{base}...{head}"], text=True)
    return [line.strip() for line in out.splitlines() if line.strip()]


def source_dirs(repo: Path) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for root_name in PACKAGE_ROOTS:
        root = repo / root_name
        if not root.is_dir():
            continue
        for makefile in root.glob("*/Makefile"):
            result[makefile.parent.name] = makefile.parent
    return result


def package_scope(source: Path) -> str:
    text = (source / "Makefile").read_text(encoding="utf-8")
    if KERNEL_RE.search(text):
        return "kernel"
    if ALL_RE.search(text):
        return "all"
    return "arch"


def source_for_path(repo: Path, relative: str) -> str | None:
    path = repo / relative
    current = path if path.is_dir() else path.parent
    while current != repo and repo in current.parents:
        if (current / "Makefile").is_file() and current.parent.name in PACKAGE_ROOTS:
            return current.name
        current = current.parent
    return None


def restriction_for_path(source: str, relative: str) -> dict[str, str]:
    parts = Path(relative).parts
    restriction: dict[str, str] = {}
    try:
        source_index = parts.index(source)
    except ValueError:
        return restriction
    tail = parts[source_index + 1 :]

    if len(tail) >= 2 and tail[0] == "releases":
        restriction["release_family"] = tail[1]

    if "patches" in tail:
        i = tail.index("patches")
        patch_tail = tail[i + 1 :]
        if len(patch_tail) >= 2 and patch_tail[0] == "arch":
            restriction["arch"] = patch_tail[1]
        elif len(patch_tail) >= 3 and patch_tail[0] == "target":
            restriction["target"] = patch_tail[1]
            restriction["subtarget"] = patch_tail[2]
    return restriction


def release_family(version: str) -> str:
    match = re.match(r"^(\d+\.\d+)", version)
    return match.group(1) if match else version


def load_contexts(path: Path) -> tuple[list[dict], list[dict], list[dict]]:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    all_contexts: dict[str, dict] = {}
    arch_contexts: list[dict] = []
    kernel_contexts: list[dict] = []
    for arch, arch_data in data["architectures"].items():
        for version, cfg in arch_data.get("versions", {}).items():
            target, subtarget = cfg["sdk_target"].split("/", 1)
            arch_contexts.append({
                "release": version,
                "arch": arch,
                "target": target,
                "subtarget": subtarget,
                "scope": "arch",
            })
            all_contexts.setdefault(version, {
                "release": version,
                "arch": "all",
                "target": target,
                "subtarget": subtarget,
                "scope": "all",
            })
            for target_spec in cfg.get("kernel_targets", []):
                kt, ks = target_spec.split("/", 1)
                kernel_contexts.append({
                    "release": version,
                    "arch": arch,
                    "target": kt,
                    "subtarget": ks,
                    "scope": "kernel",
                })
    return list(all_contexts.values()), arch_contexts, kernel_contexts


def context_matches(context: dict, restriction: dict[str, str]) -> bool:
    if restriction.get("arch") and context["arch"] != restriction["arch"]:
        return False
    if restriction.get("target") and context["target"] != restriction["target"]:
        return False
    if restriction.get("subtarget") and context["subtarget"] != restriction["subtarget"]:
        return False
    family = restriction.get("release_family")
    if family and release_family(context["release"]) != family:
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base")
    parser.add_argument("--head")
    parser.add_argument("--package", default="")
    parser.add_argument("--matrix", default="repository/build-matrix.toml")
    parser.add_argument("--rules", default="repository/rebuild-dependents.json")
    args = parser.parse_args()

    repo = Path.cwd().resolve()
    sources = source_dirs(repo)
    all_ctx, arch_ctx, kernel_ctx = load_contexts(repo / args.matrix)

    requested = args.package.strip()
    restrictions: dict[str, list[dict[str, str]]] = {}
    changed_sources: set[str] = set()

    if requested:
        if requested == "all":
            changed_sources = set(sources)
        else:
            for item in requested.split():
                if item not in sources:
                    raise SystemExit(f"ERROR: unknown package source: {item}")
                changed_sources.add(item)
                restrictions[item] = [{}]
    else:
        if not args.base or not args.head:
            raise SystemExit("ERROR: --base and --head are required when --package is empty")
        changed = git_changed_files(args.base, args.head)
        # Build-matrix or shared helper changes can affect every package/context.
        if any(p == args.matrix or p.startswith(("include/", "scripts/prepare-openwrt-derived.py")) for p in changed):
            changed_sources = set(sources)
        else:
            for relative in changed:
                if relative.startswith(IGNORED_PREFIXES) or relative.startswith("repository/"):
                    continue
                source = source_for_path(repo, relative)
                if not source:
                    continue
                changed_sources.add(source)
                restrictions.setdefault(source, []).append(restriction_for_path(source, relative))

    if not changed_sources:
        print(json.dumps({"include": []}, separators=(",", ":")))
        return 0

    rules_path = repo / args.rules
    rules = json.loads(rules_path.read_text(encoding="utf-8")) if rules_path.is_file() else {}
    dependents = rules.get("rebuild_dependents", {})
    queue = deque(sorted(changed_sources))
    while queue:
        source = queue.popleft()
        inherited = restrictions.get(source, [{}]) or [{}]
        for dependent in dependents.get(source, []):
            if dependent not in sources:
                continue
            if dependent not in changed_sources:
                changed_sources.add(dependent)
                restrictions[dependent] = list(inherited)
                queue.append(dependent)
            else:
                restrictions.setdefault(dependent, []).extend(inherited)

    matrix: list[dict] = []
    seen: set[tuple] = set()
    for source in sorted(changed_sources):
        scope = package_scope(sources[source])
        contexts = all_ctx if scope == "all" else arch_ctx if scope == "arch" else kernel_ctx
        source_restrictions = restrictions.get(source, [{}]) or [{}]
        unrestricted = any(not item for item in source_restrictions)
        for context in contexts:
            if not unrestricted and not any(context_matches(context, item) for item in source_restrictions):
                continue
            key = (source, context["release"], context["arch"], context["target"], context["subtarget"], scope)
            if key in seen:
                continue
            seen.add(key)
            matrix.append({"package": source, **context})

    print(json.dumps({"include": matrix}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
