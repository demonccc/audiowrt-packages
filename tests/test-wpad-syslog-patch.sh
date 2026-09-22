#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src/utils"

# This is the exact upstream wpa_debug.h section targeted by the package patch.
cat > "$work/src/utils/wpa_debug.h" <<'HEADER'
enum hostapd_logger_level {
	HOSTAPD_LEVEL_DEBUG_VERBOSE = 0,
	HOSTAPD_LEVEL_DEBUG = 1,
	HOSTAPD_LEVEL_INFO = 2,
	HOSTAPD_LEVEL_NOTICE = 3,
	HOSTAPD_LEVEL_WARNING = 4
};


#ifdef CONFIG_DEBUG_SYSLOG

void wpa_debug_open_syslog(void);
void wpa_debug_close_syslog(void);

#else /* CONFIG_DEBUG_SYSLOG */

static inline void wpa_debug_open_syslog(void)
{
}

static inline void wpa_debug_close_syslog(void)
{
}

#endif /* CONFIG_DEBUG_SYSLOG */
HEADER

patch --batch --fuzz=0 -p1 -d "$work" \
    -i "$repo_root/audiowrt-wpad/patches/900-noop-syslog-without-debug.patch"

cat > "$work/check.c" <<'SOURCE'
#include "src/utils/wpa_debug.h"
int main(void)
{
	wpa_debug_open_syslog();
	wpa_debug_close_syslog();
	return 0;
}
SOURCE

cc -Werror -Wall -Wextra -DCONFIG_DEBUG_SYSLOG -DCONFIG_NO_STDOUT_DEBUG \
    -I"$work" -o "$work/noop" "$work/check.c"
"$work/noop"
cc -Werror -Wall -Wextra -DCONFIG_DEBUG_SYSLOG -I"$work" \
    -c -o "$work/syslog.o" "$work/check.c"
cc -Werror -Wall -Wextra -I"$work" -o "$work/no-debug" "$work/check.c"
"$work/no-debug"

echo 'wpad syslog patch applies cleanly and all syslog configurations compile.'
