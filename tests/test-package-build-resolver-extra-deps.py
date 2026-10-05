#!/usr/bin/env python3
import subprocess
import tempfile
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
resolver = repo / "scripts" / "resolve-package-build-targets.py"

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / "config" / "build").mkdir(parents=True)
    (root / "audiowrt" / "consumer").mkdir(parents=True)
    (root / "trimmed" / "runtime-provider").mkdir(parents=True)

    targets = root / "config" / "build" / "package-build-targets"
    targets.write_text(
        "runtime-provider|package/feeds/audiowrt/runtime-provider/compile\n"
        "consumer|package/feeds/audiowrt/consumer/compile\n",
        encoding="utf-8",
    )

    packageinfo = root / "packageinfo"
    packageinfo.write_text(
        "Package: runtime-provider\n"
        "Depends: libc\n"
        "\n"
        "Package: consumer\n"
        "Depends: libc\n",
        encoding="utf-8",
    )

    (root / "trimmed" / "runtime-provider" / "Makefile").write_text(
        "define Package/runtime-provider\nendef\n",
        encoding="utf-8",
    )
    (root / "audiowrt" / "consumer" / "Makefile").write_text(
        "define Package/consumer\n"
        "  EXTRA_DEPENDS:=runtime-provider (>=0)\n"
        "endef\n",
        encoding="utf-8",
    )

    result = subprocess.run(
        ["python3", str(resolver), str(targets), str(packageinfo), "consumer"],
        check=True,
        text=True,
        capture_output=True,
    )
    lines = result.stdout.strip().splitlines()
    assert lines == [
        "runtime-provider|package/feeds/audiowrt/runtime-provider/compile",
        "consumer|package/feeds/audiowrt/consumer/compile",
    ], lines

print("EXTRA_DEPENDS build-closure test passed")
