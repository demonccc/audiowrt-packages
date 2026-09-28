#!/bin/sh
set -eu

ROOT=/tmp/audiowrt-theme-test
STATIC="$ROOT/luci-static"
THEMES="$ROOT/themes"
ORIGINAL_RES="$ROOT/original-resources"
STATE="$ROOT/state"
RAW_BASE='https://raw.githubusercontent.com/demonccc/audiowrt-packages/feat/luci-theme-audiowrt/luci-theme-audiowrt'
RAW_STATIC="$RAW_BASE/htdocs/luci-static/audiowrt"
RAW_HEADER="$RAW_BASE/ucode/template/themes/audiowrt/header.ut"

restart_luci() {
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null || true
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
	/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
}

unmount_test() {
	umount /www/luci-static/resources 2>/dev/null || true
	umount /usr/share/ucode/luci/template/themes 2>/dev/null || true
	umount /www/luci-static 2>/dev/null || true
	umount "$ORIGINAL_RES" 2>/dev/null || true
}

stop_test() {
	if [ -f "$STATE" ]; then
		old_media=$(sed -n 's/^media=//p' "$STATE")
		if [ -n "$old_media" ]; then
			uci set "luci.main.mediaurlbase=$old_media"
		else
			uci -q delete luci.main.mediaurlbase || true
		fi
		if ! grep -q '^theme_existed=1$' "$STATE"; then
			uci -q delete luci.themes.AudioWRT || true
		fi
	fi

	unmount_test
	restart_luci
	rm -rf "$ROOT"
	echo 'AudioWRT theme RAM test stopped.'
}

start_test() {
	unmount_test
	rm -rf "$ROOT"
	mkdir -p "$STATIC" "$THEMES" "$ORIGINAL_RES"

	old_media=$(uci -q get luci.main.mediaurlbase 2>/dev/null || true)
	if uci -q get luci.themes.AudioWRT >/dev/null 2>&1; then
		theme_existed=1
	else
		theme_existed=0
	fi
	printf 'media=%s\ntheme_existed=%s\n' "$old_media" "$theme_existed" > "$STATE"

	# Keep a live bind reference to the router's original LuCI resource tree.
	# The parent /www/luci-static is overmounted later, so copying alone is not
	# sufficient for symlinked modules such as resources/tools/network.js.
	mount --bind /www/luci-static/resources "$ORIGINAL_RES"

	cp -aL /www/luci-static/. "$STATIC/"
	cp -aL /usr/share/ucode/luci/template/themes/. "$THEMES/"
	mkdir -p "$STATIC/audiowrt" "$THEMES/audiowrt"

	uclient-fetch -O "$STATIC/audiowrt/cascade.css" "$RAW_STATIC/cascade.css"
	uclient-fetch -O "$STATIC/audiowrt/override.css" "$RAW_STATIC/override.css"
	uclient-fetch -O "$STATIC/audiowrt/mobile.css" "$RAW_STATIC/mobile.css"
	uclient-fetch -O "$STATIC/audiowrt/logo.svg" "$RAW_STATIC/logo.svg"
	uclient-fetch -O "$STATIC/audiowrt/logo-horizontal.svg" "$RAW_STATIC/logo-horizontal.svg"
	uclient-fetch -O "$THEMES/audiowrt/header.ut" "$RAW_HEADER"

	ln -sf ../bootstrap/footer.ut "$THEMES/audiowrt/footer.ut"
	ln -sf ../bootstrap/sysauth.ut "$THEMES/audiowrt/sysauth.ut"

	mount --bind "$STATIC" /www/luci-static
	# Re-expose the untouched original LuCI JS/resources tree inside the test
	# mount. This prevents Status -> Routes and other stock views from losing
	# modules that are outside the theme itself.
	mount --bind "$ORIGINAL_RES" /www/luci-static/resources
	mount --bind "$THEMES" /usr/share/ucode/luci/template/themes

	uci set luci.themes.AudioWRT='/luci-static/audiowrt'
	uci set luci.main.mediaurlbase='/luci-static/audiowrt'
	restart_luci

	echo 'AudioWRT theme mounted from RAM.'
	echo 'Open LuCI and hard-refresh the browser (Ctrl+F5).'
	echo 'Nothing was committed to flash.'
}

case "${1:-start}" in
	start) start_test ;;
	stop) stop_test ;;
	restart) stop_test; start_test ;;
	*) echo "Usage: $0 {start|stop|restart}" >&2; exit 2 ;;
esac
