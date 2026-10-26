#!/usr/bin/env python3
"""Resolve AudioWRT packages affected by a git diff.

The package directory is the nearest ancestor containing a Makefile with one or
more `define Package/<name>` declarations. Shared build infrastructure changes
fall back to `all`. Optional rebuild_dependents rules propagate rebuilds only
where AudioWRT explicitly requires it; runtime dependencies do not imply a
rebuild by themselves.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from collections import deque
from pathlib import Path

PACKAGE_RE = re.compile(r"^define Package/([^\s]+)", re.MULTILINE)
SHARED_PREFIXES = ("include/", "scripts/")


def git_changed_files(base: str, head: str) -> list[str]:
    output = subprocess.check_output(
        ["git", "diff", "--name-only", f"{base}...{head}"], text=True
    )
    return [line.strip() for line in output.splitlines() if line.strip()]


def package_names_for_path(repo: Path, relative: str) -> set[str]:
    path = repo / relative
    current = path if path.is_dir() else path.parent
    while current != repo and repo in current.parents:
        makefile = current / "Makefile"
        if makefile.is_file():
            names = set(PACKAGE_RE.findall(makefile.read_text(encoding="utf-8")))
            if names:
                return names
        current = current.parent
    return set()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("base")
    parser.add_argument("head")
    parser.add_argument("--rules", default="repository/rebuild-dependents.json")
    args = parser.parse_args()

    repo = Path.cwd().resolve()
    changed = git_changed_files(args.base, args.head)
    if not changed:
        print("")
        return 0

    if any(path.startswith(SHARED_PREFIXES) for path in changed):
        print("all")
        return 0

    affected: set[str] = set()
    unresolved_package_change = False
    for relative in changed:
        if relative.startswith(("docs/", ".github/", "repository/")):
            continue
        names = package_names_for_path(repo, relative)
        if names:
            affected.update(names)
        else:
            unresolved_package_change = True

    if unresolved_package_change:
        print("all")
        return 0
    if not affected:
        print("")
        return 0

    rules_path = repo / args.rules
    rules = json.loads(rules_path.read_text(encoding="utf-8")) if rules_path.is_file() else {}
    dependents = rules.get("rebuild_dependents", {})

    queue = deque(sorted(affected))
    while queue:
        package = queue.popleft()
        for dependent in dependents.get(package, []):
            if dependent not in affected:
                affected.add(dependent)
                queue.append(dependent)

    print(" ".join(sorted(affected)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
