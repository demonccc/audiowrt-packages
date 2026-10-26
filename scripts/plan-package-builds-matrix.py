#!/usr/bin/env python3
"""Wrap the repository-state planner and expose PKGARCH=all as its own CI job.

The underlying package planner intentionally treats architecture-independent
packages as one build per OpenWrt release. This wrapper keeps that state model
but moves those tasks out of the first physical architecture job. x86_64 is
used only as the SDK execution context; published package architecture remains
`all`.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tomllib
from pathlib import Path


def matrix_path(args: list[str]) -> Path:
    if "--matrix" in args:
        index = args.index("--matrix")
        if index + 1 >= len(args):
            raise SystemExit("ERROR: --matrix requires a value")
        return Path(args[index + 1])
    return Path("repository/build-matrix.toml")


def all_contexts(path: Path) -> dict[str, tuple[str, str]]:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    x86 = data.get("architectures", {}).get("x86_64", {})
    result: dict[str, tuple[str, str]] = {}
    for release, cfg in x86.get("versions", {}).items():
        target, subtarget = cfg["sdk_target"].split("/", 1)
        result[release] = (target, subtarget)
    return result


def main() -> int:
    args = sys.argv[1:]
    raw = subprocess.check_output(
        [sys.executable, "scripts/plan-package-builds.py", *args], text=True
    )
    planned = json.loads(raw)
    references = all_contexts(matrix_path(args))

    normal: list[dict] = []
    all_jobs: dict[str, dict] = {}

    for entry in planned.get("include", []):
        release = entry["release"]
        regular_tasks = []
        all_tasks = []
        for task in json.loads(entry["tasks_json"]):
            if task.get("scope") == "all":
                all_tasks.append(task)
            else:
                regular_tasks.append(task)

        if regular_tasks:
            copy = dict(entry)
            copy["tasks_json"] = json.dumps(regular_tasks, separators=(",", ":"))
            copy["task_count"] = len(regular_tasks)
            normal.append(copy)

        if all_tasks:
            if release not in references:
                raise SystemExit(
                    f"ERROR: no x86_64 SDK reference configured for OpenWrt {release}"
                )
            target, subtarget = references[release]
            all_entry = all_jobs.setdefault(
                release,
                {"release": release, "arch": "all", "tasks": []},
            )
            for task in all_tasks:
                rewritten = dict(task)
                rewritten["target"] = target
                rewritten["subtarget"] = subtarget
                if rewritten not in all_entry["tasks"]:
                    all_entry["tasks"].append(rewritten)

    result = []
    for release, entry in sorted(all_jobs.items()):
        tasks = sorted(entry["tasks"], key=lambda x: (x["scope"], x["package"]))
        result.append({
            "release": release,
            "arch": "all",
            "tasks_json": json.dumps(tasks, separators=(",", ":")),
            "task_count": len(tasks),
        })
    result.extend(sorted(normal, key=lambda x: (x["release"], x["arch"])))

    print(json.dumps({"include": result}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
