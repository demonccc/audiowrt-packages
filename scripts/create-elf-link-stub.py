#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Create a build-only shared-library stub from an exact runtime ELF.

OpenWrt release APKs are aggressively stripped and cannot be consumed directly
by GNU ld as development libraries. Their dynamic symbol table is still enough
for AudioWRT package linking, so this helper mirrors exported FUNC/OBJECT
symbols into a tiny target-architecture shared object with the original SONAME.
The stub is used only in the SDK; firmware always installs the official APK.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path


IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
CRT_PROVIDED_SYMBOLS = {"_init", "_fini"}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def dynamic_symbols(readelf: str, library: Path) -> list[tuple[str, str, int]]:
    proc = subprocess.run(
        [readelf, "-D", "-s", "-W", str(library)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )

    symbols: dict[str, tuple[str, int]] = {}
    for raw in proc.stdout.splitlines():
        parts = raw.split()
        if len(parts) < 8 or not parts[0].rstrip(":").isdigit():
            continue

        sym_type = parts[3]
        bind = parts[4]
        ndx = parts[6]
        name = parts[7].split("@", 1)[0]
        if (
            sym_type not in {"FUNC", "OBJECT"}
            or bind not in {"GLOBAL", "WEAK"}
            or ndx == "UND"
            or name in CRT_PROVIDED_SYMBOLS
            or not IDENT.fullmatch(name)
        ):
            continue

        try:
            size = int(parts[2], 0)
        except ValueError:
            size = 0

        previous = symbols.get(name)
        if previous is None or (previous[0] != "FUNC" and sym_type == "FUNC"):
            symbols[name] = (sym_type, size)

    if not symbols:
        fail(f"no usable dynamic symbols found in {library}")

    return [(name, kind, size) for name, (kind, size) in sorted(symbols.items())]


def main() -> None:
    if len(sys.argv) != 6:
        fail(
            "usage: create-elf-link-stub.py "
            "<readelf> <target-cc> <runtime-library> <output-library> <soname>"
        )

    readelf, cc, library_arg, output_arg, soname = sys.argv[1:]
    library = Path(library_arg)
    output = Path(output_arg)
    if not library.is_file():
        fail(f"runtime library not found: {library}")
    if not soname or "/" in soname:
        fail(f"invalid SONAME: {soname!r}")

    symbols = dynamic_symbols(readelf, library)
    output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="audiowrt-elf-stub-") as tmp:
        source = Path(tmp) / "stub.c"
        lines = [
            "/* Generated build-only link stub; never shipped in firmware. */",
            "#include <stddef.h>",
        ]
        for name, kind, size in symbols:
            if kind == "FUNC":
                lines.append(
                    f'__attribute__((visibility("default"))) void {name}(void) {{}}'
                )
            else:
                extent = max(size, 1)
                lines.append(
                    f'__attribute__((visibility("default"))) '
                    f'unsigned char {name}[{extent}];'
                )
        source.write_text("\n".join(lines) + "\n", encoding="utf-8")

        subprocess.run(
            [
                cc,
                "-shared",
                "-fPIC",
                f"-Wl,-soname,{soname}",
                "-o",
                str(output),
                str(source),
            ],
            check=True,
        )


if __name__ == "__main__":
    main()
