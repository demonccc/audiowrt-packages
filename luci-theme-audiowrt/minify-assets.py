#!/usr/bin/env python3
"""Build-time minifier for the AudioWRT LuCI theme."""
from __future__ import annotations
import argparse
import re
from pathlib import Path
BOOTSTRAP_IMPORT = "@import url('/luci-static/bootstrap/cascade.css');"
def strip_block_comments(text: str) -> str:
    out=[]; i=0; quote=None
    while i < len(text):
        ch=text[i]
        if quote:
            out.append(ch)
            if ch == "\\" and i + 1 < len(text):
                i += 1; out.append(text[i])
            elif ch == quote:
                quote=None
            i += 1; continue
        if ch in ("'", '"'):
            quote=ch; out.append(ch); i += 1; continue
        if ch == "/" and i + 1 < len(text) and text[i+1] == "*":
            end=text.find("*/", i+2); i=len(text) if end < 0 else end+2; continue
        out.append(ch); i += 1
    return "".join(out)
def minify_css(text: str) -> str:
    text=text.replace(BOOTSTRAP_IMPORT, "")
    text=strip_block_comments(text)
    text=" ".join(line.strip() for line in text.splitlines() if line.strip())
    text=re.sub(r"\s*([{}:;,>~])\s*", r"\1", text)
    return text.replace(";}", "}").strip()+"\n"
def minify_js(text: str) -> str:
    text=strip_block_comments(text)
    lines=[]
    for line in text.splitlines():
        stripped=line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        lines.append(stripped)
    return "\n".join(lines)+"\n"
def main() -> None:
    p=argparse.ArgumentParser(); p.add_argument("kind", choices=("css","js")); p.add_argument("output"); p.add_argument("inputs", nargs="+"); a=p.parse_args()
    source="\n".join(Path(path).read_text(encoding="utf-8") for path in a.inputs)
    Path(a.output).write_text(minify_css(source) if a.kind == "css" else minify_js(source), encoding="utf-8")
if __name__ == "__main__": main()
