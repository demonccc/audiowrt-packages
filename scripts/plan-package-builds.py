#!/usr/bin/env python3
"""Plan pending AudioWRT package builds grouped by package architecture.

Automatic builds are repository-state driven: each package/context is compared
with its last successfully published source commit. Missing contexts and changes
that happened after a failed build remain pending on later merges. The resulting
GitHub Actions matrix contains at most one job per OpenWrt release + package
architecture, with the pending package tasks embedded in that job.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import tomllib
import urllib.request
from collections import deque
from pathlib import Path

KERNEL_RE = re.compile(r"^define KernelPackage/([^\s]+)", re.MULTILINE)
ALL_RE = re.compile(r"^\s*PKGARCH\s*:?=\s*all\s*$", re.MULTILINE)
PACKAGE_ROOTS = ("audiowrt", "ported", "trimmed", "tailored")
API = "https://api.github.com"


def git_changed_files(base: str, head: str) -> list[str]:
    if base == head:
        return []
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


def request_json(url: str, token: str, *, asset: bool = False):
    headers = {
        "Accept": "application/octet-stream" if asset else "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "AudioWRT-package-planner",
    }
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers)) as response:
        raw = response.read()
    return json.loads(raw.decode("utf-8"))


def published_state(repository: str, channel: str, token: str) -> dict[tuple, str]:
    """Return latest successful source commit per package-source build context."""
    state: dict[tuple, tuple[str, str]] = {}
    page = 1
    while True:
        releases = request_json(f"{API}/repos/{repository}/releases?per_page=100&page={page}", token)
        if not releases:
            break
        for release in releases:
            asset = next((a for a in release.get("assets", []) if a.get("name") == "repository-update.json"), None)
            if not asset:
                continue
            update = request_json(asset["url"], token, asset=True)
            if update.get("schema", 0) < 2 or update.get("channel") != channel:
                continue
            scope = update.get("scope")
            version = update.get("openwrt_version")
            arch = update.get("architecture")
            target = update.get("target")
            subtarget = update.get("subtarget")
            published_at = release.get("published_at") or release.get("created_at") or ""
            for package in update.get("packages", {}).values():
                source_dir = package.get("source_dir", "")
                source = Path(source_dir).name if source_dir else ""
                source_commit = package.get("source_commit") or update.get("source_commit")
                if not source or not source_commit:
                    continue
                if scope == "all":
                    key = (source, version, "all", "", "")
                elif scope == "arch":
                    key = (source, version, arch, "", "")
                elif scope == "kernel":
                    key = (source, version, arch, target, subtarget)
                else:
                    continue
                previous = state.get(key)
                if previous is None or published_at >= previous[0]:
                    state[key] = (published_at, source_commit)
        if len(releases) < 100:
            break
        page += 1
    return {key: value[1] for key, value in state.items()}


def affected_sources(
    repo: Path,
    changed: list[str],
    sources: dict[str, Path],
    dependents: dict[str, list[str]],
) -> dict[str, list[dict[str, str]]]:
    restrictions: dict[str, list[dict[str, str]]] = {}
    changed_sources: set[str] = set()
    for relative in changed:
        source = source_for_path(repo, relative)
        if not source:
            continue
        changed_sources.add(source)
        restrictions.setdefault(source, []).append(restriction_for_path(source, relative))

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
    return restrictions


def task_key(source: str, scope: str, context: dict) -> tuple:
    if scope == "all":
        return (source, context["release"], "all", "", "")
    if scope == "arch":
        return (source, context["release"], context["arch"], "", "")
    return (
        source,
        context["release"],
        context["arch"],
        context["target"],
        context["subtarget"],
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--package", default="")
    parser.add_argument("--matrix", default="repository/build-matrix.toml")
    parser.add_argument("--rules", default="repository/rebuild-dependents.json")
    parser.add_argument("--repository", default="")
    parser.add_argument("--channel", choices=("stable", "testing"))
    parser.add_argument("--token-env", default="GITHUB_TOKEN")
    args = parser.parse_args()

    repo = Path.cwd().resolve()
    sources = source_dirs(repo)
    arch_ctx, kernel_ctx = load_contexts(repo / args.matrix)
    rules_path = repo / args.rules
    rules = json.loads(rules_path.read_text(encoding="utf-8")) if rules_path.is_file() else {}
    dependents = rules.get("rebuild_dependents", {})

    requested = args.package.strip()
    explicit_restrictions: dict[str, list[dict[str, str]]] | None = None
    state: dict[tuple, str] = {}

    if requested:
        if requested == "all":
            explicit_restrictions = {source: [{}] for source in sources}
        else:
            explicit_restrictions = {}
            for item in requested.split():
                if item not in sources:
                    raise SystemExit(f"ERROR: unknown package source: {item}")
                explicit_restrictions[item] = [{}]
    elif args.repository and args.channel:
        token = os.environ.get(args.token_env, "")
        if not token:
            raise SystemExit(f"ERROR: {args.token_env} is required for repository-state planning")
        state = published_state(args.repository, args.channel, token)
    elif args.base:
        # Local/test fallback: plan only the supplied git delta.
        explicit_restrictions = affected_sources(
            repo, git_changed_files(args.base, args.head), sources, dependents
        )
    else:
        raise SystemExit("ERROR: automatic planning requires --repository and --channel")

    diff_cache: dict[str, dict[str, list[dict[str, str]]]] = {}

    def task_is_pending(source: str, scope: str, context: dict) -> bool:
        if explicit_restrictions is not None:
            source_restrictions = explicit_restrictions.get(source)
            if not source_restrictions:
                return False
            unrestricted = any(not item for item in source_restrictions)
            return unrestricted or any(context_matches(context, item) for item in source_restrictions)

        previous = state.get(task_key(source, scope, context))
        if not previous:
            return True
        if previous == args.head or previous == subprocess.check_output(["git", "rev-parse", args.head], text=True).strip():
            return False
        if previous not in diff_cache:
            diff_cache[previous] = affected_sources(
                repo, git_changed_files(previous, args.head), sources, dependents
            )
        source_restrictions = diff_cache[previous].get(source)
        if not source_restrictions:
            return False
        unrestricted = any(not item for item in source_restrictions)
        return unrestricted or any(context_matches(context, item) for item in source_restrictions)

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

    for source in sorted(sources):
        scope = package_scope(sources[source])
        contexts = kernel_ctx if scope == "kernel" else arch_ctx

        if scope == "all":
            by_release: dict[str, dict] = {}
            for context in contexts:
                by_release.setdefault(context["release"], context)
            contexts = list(by_release.values())

        for context in contexts:
            if task_is_pending(source, scope, context):
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
