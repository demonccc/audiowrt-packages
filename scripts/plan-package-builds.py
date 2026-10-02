#!/usr/bin/env python3
"""Plan incremental AudioWRT builds grouped by architecture.

Automatic builds are driven only by changes inside package source directories.
Each matrix entry represents one OpenWrt release + package architecture and
contains only the package build tasks affected by the git delta. Architecture-
specific and target-specific patches narrow the affected contexts further.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import tomllib
from collections import deque
from pathlib import Path

KERNEL_RE = re.compile(r"^define KernelPackage/([^\s]+)", re.MULTILINE)
ALL_RE = re.compile(r"^\s*PKGARCH\s*:?=\s*all\s*$", re.MULTILINE)
PACKAGE_ROOTS = ("audiowrt", "ported", "trimmed", "tailored")


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


def load_contexts(path: Path) -> tuple[list[dict], list[dict]]:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
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
            })
            for target_spec in cfg.get("kernel_targets", []):
                kt, ks = target_spec.split("/", 1)
                kernel_contexts.append({
                    "release": version,
                    "arch": arch,
                    "target": kt,
                    "subtarget": ks,
                })
    return arch_contexts, kernel_contexts


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
    arch_ctx, kernel_ctx = load_contexts(repo / args.matrix)

    requested = args.package.strip()
    restrictions: dict[str, list[dict[str, str]]] = {}
    changed_sources: set[str] = set()

    if requested:
        if requested == "all":
            changed_sources = set(sources)
            restrictions = {source: [{}] for source in sources}
        else:
            for item in requested.split():
                if item not in sources:
                    raise SystemExit(f"ERROR: unknown package source: {item}")
                changed_sources.add(item)
                restrictions[item] = [{}]
    else:
        if not args.base or not args.head:
            raise SystemExit("ERROR: --base and --head are required when --package is empty")
        for relative in git_changed_files(args.base, args.head):
            source = source_for_path(repo, relative)
            if not source:
                # CI/tooling/repository metadata changes never bootstrap every
                # package automatically. A full rebuild remains available via
                # workflow_dispatch package=all.
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

    # Group tasks by release + architecture. This is the important boundary:
    # GitHub Actions creates at most one job for an affected architecture,
    # never one job per package.
    grouped: dict[tuple[str, str], dict] = {}

    def add_task(context: dict, source: str, scope: str) -> None:
        key = (context["release"], context["arch"])
        entry = grouped.setdefault(key, {
            "release": context["release"],
            "arch": context["arch"],
            "tasks": [],
        })
        task = {
            "package": source,
            "scope": scope,
            "target": context["target"],
            "subtarget": context["subtarget"],
        }
        if task not in entry["tasks"]:
            entry["tasks"].append(task)

    for source in sorted(changed_sources):
        scope = package_scope(sources[source])
        source_restrictions = restrictions.get(source, [{}]) or [{}]
        unrestricted = any(not item for item in source_restrictions)

        if scope == "kernel":
            contexts = kernel_ctx
        else:
            contexts = arch_ctx

        matching = [
            context for context in contexts
            if unrestricted or any(context_matches(context, item) for item in source_restrictions)
        ]

        if scope == "all":
            # Architecture-independent packages are built exactly once per
            # release, using the first matching SDK context for that release.
            by_release: dict[str, dict] = {}
            for context in matching:
                by_release.setdefault(context["release"], context)
            matching = list(by_release.values())

        for context in matching:
            add_task(context, source, scope)

    matrix = []
    for _, entry in sorted(grouped.items()):
        entry["tasks"].sort(key=lambda x: (x["target"], x["subtarget"], x["scope"], x["package"]))
        matrix.append({
            "release": entry["release"],
            "arch": entry["arch"],
            "tasks_json": json.dumps(entry["tasks"], separators=(",", ":")),
            "task_count": len(entry["tasks"]),
        })

    print(json.dumps({"include": matrix}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
