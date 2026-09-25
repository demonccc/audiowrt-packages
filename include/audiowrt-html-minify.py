#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import re
import subprocess
import sys
from pathlib import Path


def minify_js(jsmin: Path, source: str) -> str:
    result = subprocess.run(
        [str(jsmin)],
        input=source,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or "jsmin failed")
    return result.stdout.strip()


def minify_css(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"\s+", " ", source).strip()
    source = re.sub(r"\s*([{}:;,])\s*", r"\1", source)
    return source


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: audiowrt-html-minify.py <jsmin> <html>")

    jsmin = Path(sys.argv[1])
    path = Path(sys.argv[2])
    html = path.read_text(encoding="utf-8")

    def script_replace(match: re.Match[str]) -> str:
        attrs, body = match.group(1), match.group(2)
        if re.search(r"\bsrc\s*=", attrs, flags=re.I):
            return match.group(0)
        return f"<script{attrs}>{minify_js(jsmin, body)}</script>"

    def style_replace(match: re.Match[str]) -> str:
        return f"<style{match.group(1)}>{minify_css(match.group(2))}</style>"

    html = re.sub(r"<!--(?!\[if\b).*?-->", "", html, flags=re.I | re.S)
    html = re.sub(r"<script([^>]*)>(.*?)</script>", script_replace, html, flags=re.I | re.S)
    html = re.sub(r"<style([^>]*)>(.*?)</style>", style_replace, html, flags=re.I | re.S)
    html = re.sub(r">\s+<", "><", html).strip() + "\n"
    path.write_text(html, encoding="utf-8")


if __name__ == "__main__":
    main()
