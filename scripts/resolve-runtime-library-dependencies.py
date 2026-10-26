#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import re
import sys
from pathlib import Path

TOOLCHAIN_PROVIDED = {"libc", "libgcc", "libpthread", "librt"}

def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)

def normalize_dependency(token: str) -> str:
    token = token.strip()
    if not token or token.startswith("@"):
        return ""
    token = token.lstrip("+")
    if ":" in token:
        token = token.rsplit(":", 1)[1]
    token = token.lstrip("+")
    token = re.split(r"[<>= ]", token, maxsplit=1)[0]
    token = token.split("/", 1)[0]
    if token.startswith("kmod-") or token == "kernel":
        return ""
    return token

def load_owned(path: Path) -> set[str]:
    owned=set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line=raw.strip()
        if not line or line.startswith("#"):
            continue
        owned.add(line.split("|",1)[0])
    return owned

def load_metadata(path: Path):
    metadata={}
    current=None
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if raw.startswith("Package:"):
            current=raw.split(":",1)[1].strip()
            metadata[current]={"runtime":[],"provides":[]}
        elif current and raw.startswith("Depends:"):
            metadata[current]["runtime"]=raw.split(":",1)[1].strip().split()
        elif current and raw.startswith("Provides:"):
            metadata[current]["provides"]=raw.split(":",1)[1].strip().split()
    return metadata

def main():
    if len(sys.argv) < 4:
        fail("usage: resolve-runtime-library-dependencies.py <package-build-targets> <packageinfo> <package>... [--providers <package>...]")
    targets=Path(sys.argv[1])
    packageinfo=Path(sys.argv[2])
    args=sys.argv[3:]
    if "--providers" in args:
        i=args.index("--providers")
        selected=args[:i]
        providers=args[i+1:]
    else:
        selected=args
        providers=list(selected)

    owned=load_owned(targets)
    metadata=load_metadata(packageinfo)
    selected_provides={
        normalize_dependency(v)
        for package in providers
        for v in metadata.get(package,{}).get("provides",[])
        if normalize_dependency(v)
    }

    seen=set()
    for package in selected:
        fields=metadata.get(package)
        if not fields:
            fail(f"package metadata not found: {package}")
        for token in fields["runtime"]:
            dep=normalize_dependency(token)
            if not dep or dep in TOOLCHAIN_PROVIDED or dep in owned or dep in selected_provides:
                continue
            if dep not in seen:
                seen.add(dep)
                print(dep)

if __name__ == "__main__":
    main()
