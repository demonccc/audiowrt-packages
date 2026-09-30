#!/usr/bin/env python3
from pathlib import Path
import sys

def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")

def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        fail(f"expected BlueALSA source anchor not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")

if len(sys.argv) != 2:
    fail("usage: disable-ctl.py <bluealsa-source-root>")

root = Path(sys.argv[1])
configure = root / "configure.ac"
asound_makefile = root / "src" / "asound" / "Makefile.am"

replace_once(
    configure,
    '''AC_PATH_PROGS([GDBUS_CODEGEN], [gdbus-codegen])
AS_IF([test "x$GDBUS_CODEGEN" = "x"], [AC_MSG_ERROR([[gdbus-codegen not found]])])

PKG_CHECK_MODULES([LIBBSD], [libbsd >= 0.8],
''',
    '''AC_PATH_PROGS([GDBUS_CODEGEN], [gdbus-codegen])
AS_IF([test "x$GDBUS_CODEGEN" = "x"], [AC_MSG_ERROR([[gdbus-codegen not found]])])

AC_ARG_ENABLE([ctl],
	[AS_HELP_STRING([--disable-ctl], [disable building of the BlueALSA ALSA control plugin])],
	[], [enable_ctl=yes])
AM_CONDITIONAL([ENABLE_CTL], [test "x$enable_ctl" != "xno"])

PKG_CHECK_MODULES([LIBBSD], [libbsd >= 0.8],
'''
)

replace_once(
    asound_makefile,
    "asound_module_ctl_LTLIBRARIES = libasound_module_ctl_bluealsa.la\n",
    """asound_module_ctl_LTLIBRARIES =
if ENABLE_CTL
asound_module_ctl_LTLIBRARIES += libasound_module_ctl_bluealsa.la
endif
"""
)
