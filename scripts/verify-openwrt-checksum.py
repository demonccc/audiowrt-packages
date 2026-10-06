#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(5)


def main() -> None:
    if len(sys.argv) != 4:
        fail("usage: verify-openwrt-checksum.py <sha256sums> <target-relative-path> <file>")

    manifest_path = Path(sys.argv[1])
    expected_path = sys.argv[2]
    download_path = Path(sys.argv[3])
    checksum_pattern = re.compile(r"^([0-9a-fA-F]{64}) [ *](.+)$")

    matches: list[str] = []
    for line in manifest_path.read_text(encoding="utf-8").splitlines():
        match = checksum_pattern.fullmatch(line)
        if match and match.group(2) == expected_path:
            matches.append(match.group(1).lower())

    if len(matches) != 1:
        fail(f"expected one OpenWrt checksum for {expected_path}, found {len(matches)}")

    actual = hashlib.sha256(download_path.read_bytes()).hexdigest()
    if actual != matches[0]:
        fail(f"OpenWrt checksum mismatch for {expected_path}")

    print(f"{download_path.name}: OK")


if __name__ == "__main__":
    main()
