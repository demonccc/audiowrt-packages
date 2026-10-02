#!/usr/bin/env python3
"""Focused tests for repository-state package planning helpers."""
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "scripts" / "plan-package-builds.py"
spec = importlib.util.spec_from_file_location("planner", MODULE)
planner = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(planner)


def test_context_restrictions() -> None:
    ctx = {
        "release": "25.12.5",
        "arch": "mips_24kc",
        "target": "ath79",
        "subtarget": "generic",
    }
    assert planner.context_matches(ctx, {})
    assert planner.context_matches(ctx, {"release_family": "25.12"})
    assert planner.context_matches(ctx, {"arch": "mips_24kc"})
    assert planner.context_matches(ctx, {"target": "ath79", "subtarget": "generic"})
    assert not planner.context_matches(ctx, {"arch": "x86_64"})
    assert not planner.context_matches(ctx, {"target": "ipq40xx", "subtarget": "generic"})


def test_task_keys() -> None:
    ctx = {
        "release": "25.12.5",
        "arch": "mips_24kc",
        "target": "ath79",
        "subtarget": "generic",
    }
    assert planner.task_key("foo", "all", ctx) == ("foo", "25.12.5", "all", "", "")
    assert planner.task_key("foo", "arch", ctx) == ("foo", "25.12.5", "mips_24kc", "", "")
    assert planner.task_key("foo", "kernel", ctx) == (
        "foo", "25.12.5", "mips_24kc", "ath79", "generic"
    )


if __name__ == "__main__":
    test_context_restrictions()
    test_task_keys()
