#!/bin/sh
set -eu

ROOT=/tmp/audiowrt-theme-test
STATIC="$ROOT/luci-static"
THEMES="$ROOT/themes"
STATE="$ROOT/state"
RAW='https://raw.githubusercontent.com/demonccc/audiowrt-packages/feat/luci-theme-audiowrt/luci-theme-audiowrt/htdocs/luci-static/audiowrt'

restart_luci() {
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null || true
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
	/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
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

	umount /usr/share/ucode/luci/template/themes 2>/dev/null || true
	umount /www/luci-static 2>/dev/null || true
	restart_luci
	rm -rf "$ROOT"
	echo 'AudioWRT theme RAM test stopped.'
}

start_test() {
	umount /usr/share/ucode/luci/template/themes 2>/dev/null || true
	umount /www/luci-static 2>/dev/null || true
	rm -rf "$ROOT"
	mkdir -p "$STATIC" "$THEMES" "$ROOT"

	old_media=$(uci -q get luci.main.mediaurlbase 2>/dev/null || true)
	if uci -q get luci.themes.AudioWRT >/dev/null 2>&1; then
		theme_existed=1
	else
		theme_existed=0
	fi
	printf 'media=%s\ntheme_existed=%s\n' "$old_media" "$theme_existed" > "$STATE"

	cp -a /www/luci-static/. "$STATIC/"
	cp -a /usr/share/ucode/luci/template/themes/. "$THEMES/"
	mkdir -p "$STATIC/audiowrt" "$THEMES/audiowrt"

	uclient-fetch -O "$STATIC/audiowrt/cascade.css" "$RAW/cascade.css"
	uclient-fetch -O "$STATIC/audiowrt/mobile.css" "$RAW/mobile.css"
	uclient-fetch -O "$STATIC/audiowrt/logo.svg" "$RAW/logo.svg"
	uclient-fetch -O "$STATIC/audiowrt/logo-horizontal.svg" "$RAW/logo-horizontal.svg"

	ln -sf ../bootstrap/logo_48.png "$STATIC/audiowrt/logo_48.png"
	ln -sf ../bootstrap/header.ut "$THEMES/audiowrt/header.ut"
	ln -sf ../bootstrap/footer.ut "$THEMES/audiowrt/footer.ut"
	ln -sf ../bootstrap/sysauth.ut "$THEMES/audiowrt/sysauth.ut"

	mount --bind "$STATIC" /www/luci-static
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
