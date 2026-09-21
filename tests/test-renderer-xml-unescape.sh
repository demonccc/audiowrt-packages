#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$repo_root/audiowrt-dlna/src/renderer-part-02.inc"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

python3 - "$source_file" "$tmpdir/test_xml_unescape.c" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text()
match = re.search(
    r"static void xml_unescape\(char \*s\)\n\{.*?\n\}\n(?=\nstatic int xml_value)",
    source,
    re.S,
)
if not match:
    raise SystemExit("xml_unescape implementation not found")

harness = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>

''' + match.group(0) + r'''

static void expect(const char *input, const char *expected)
{
    char buf[512];
    snprintf(buf, sizeof(buf), "%s", input);
    xml_unescape(buf);
    if (strcmp(buf, expected)) {
        fprintf(stderr, "xml_unescape(%s) => %s, expected %s\n", input, buf, expected);
        exit(1);
    }
}

int main(void)
{
    expect("&amp;", "&");
    expect("&lt;tag&gt;", "<tag>");
    expect("&quot;A&amp;B&quot;", "\"A&B\"");
    expect("&amp;amp;", "&amp;");
    expect("&amp;lt;tag&amp;gt;", "&lt;tag&gt;");
    expect("https://x/?a=1&amp;amp;b=2", "https://x/?a=1&amp;b=2");
    return 0;
}
'''
Path(sys.argv[2]).write_text(harness)
PY

cc -std=c99 -Wall -Wextra -Werror "$tmpdir/test_xml_unescape.c" -o "$tmpdir/test_xml_unescape"
"$tmpdir/test_xml_unescape"

echo "renderer XML one-layer unescape contract OK"
