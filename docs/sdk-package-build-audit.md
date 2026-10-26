# SDK build audit: canonical AudioWRT 8eb72f8 versus standalone builder

Canonical reference: demonccc/audiowrt@8eb72f8cd7b0cce129c960bab1de00521c5d88cd, scripts/build.sh and config/build/{package-build-targets,source-build-packages}. The reference repository contains no package Makefiles; the 43 standalone Makefiles were inspected in the current feed. Consequently names not present in the canonical target map are marked as such rather than claimed as original implementations.

**IMPORTANT:** NO_DEPS prevents recursive OpenWrt dependency compilation; it does **not** prevent the target's own source being compiled. Source classification is for the four packages whose upstream development dependencies must resolve via OpenWrt. A customized native package may compile its own source in NO_DEPS mode.

| Current package | Original map | Recipe behavior | SDK dependency strategy |
|---|---|---|---|
| audiowrt-distro-branding | audiowrt-branding | assets/config | NO_DEPS |
| audiowrt-config | audiowrt-config | assets/config | NO_DEPS |
| audiowrt-core | audiowrt-core | assets/config | NO_DEPS |
| audiowrt-provisioning | audiowrt-provisioning | assets/config | NO_DEPS |
| luci-app-audiowrt-core | luci-app-audiowrt-core | assets/config | NO_DEPS |
| luci-theme-audiowrt | luci-theme-audiowrt | assets/config | NO_DEPS |
| luci-mod-status-tailored | not in canonical map | custom C/assets | NO_DEPS |
| kmod-bluetooth-tailored | kmod-audiowrt-bluetooth | official APK -> select .ko | NO_DEPS |
| busybox-udhcpd-tailored | audiowrt-udhcpd / audiowrt-busybox | derived upstream source | NO_DEPS |
| dropbear-trimmed | audiowrt-dropbear | derived upstream source | NO_DEPS |
| dbus-trimmed | not in canonical map | official APK -> subset | NO_DEPS |
| audiowrt-audio | audiowrt-audio | assets/config | NO_DEPS |
| alsa-lib-trimmed | libaudiowrt-alsa-minimal | derived upstream source | NO_DEPS |
| hostapd-wpa-supplicant-tailored | audiowrt-wpad | derived upstream source + SDK headers/stubs | NO_DEPS |
| umdns-trimmed | audiowrt-umdns | derived upstream source | NO_DEPS |
| audiowrt-usb-audio | audiowrt-usb-audio | assets/config | NO_DEPS |
| audiowrt-network-client | audiowrt-network-client | assets/config | NO_DEPS |
| audiowrt-wifi-client | audiowrt-wifi-client | assets/config | NO_DEPS |
| audiowrt-player-mpd | audiowrt-mpd | assets/config | NO_DEPS |
| audiowrt-dlna-renderer | audiowrt-renderer | assets/config | NO_DEPS |
| libaudiowrt-player | libaudiowrt-player | local C code | NO_DEPS |
| audiowrt-player-flac | same | local C code | NO_DEPS |
| audiowrt-player-mp3 | same | local C code | NO_DEPS |
| audiowrt-player-aac | same | local C code | NO_DEPS |
| audiowrt-player-m4a | same | local C code | NO_DEPS |
| audiowrt-player-lpcm | same | local C code | NO_DEPS |
| audiowrt-player-wav | same | local C code | NO_DEPS |
| audiowrt-player-vorbis | same | local C code | NO_DEPS |
| audiowrt-player-aiff | same | local C code | NO_DEPS |
| audiowrt-player-opus | same | local C code | NO_DEPS |
| audiowrt-player-ffmpeg | same | local C code | NO_DEPS |
| luci-app-audiowrt-dlna-renderer | luci-app-audiowrt-renderer | assets/config | NO_DEPS |
| audiowrt-airplay | same | assets/config | NO_DEPS |
| audiowrt-spotify | same | assets/config | NO_DEPS |
| sbc-trimmed | audiowrt-sbc | derived upstream source | NO_DEPS |
| glib2-trimmed | not in canonical map | official APK -> subset | NO_DEPS |
| bluez-trimmed | audiowrt-bluez | derived upstream source | SOURCE |
| audiowrt-btctl | same | local C code + GLib headers | SOURCE |
| bluez-alsa | same | upstream C source | SOURCE |
| audiowrt-bluetooth | same | assets/config | NO_DEPS |
| luci-app-audiowrt | same | assets/config | NO_DEPS |
| luci-app-audiowrt-network-client | same | assets/config | NO_DEPS |
| librespot | same | upstream Rust source | SOURCE |

## Invariants

- Never rebuild an official runtime dependency simply because it appears in DEPENDS.
- Package-only targets build with NO_DEPS=1. Only four genuine source targets follow their SDK dependency graph.
- libaudiowrt-player and native decoder C code are *real local compilations*, but can remain NO_DEPS because the builder stages their precise public headers and official link stubs.
- dbus-trimmed and glib2-trimmed are APK repackaging recipes; kmod-bluetooth-tailored stages verified exact-release APK .ko files in a private SDK recipe.
- The derived-source recipes for BusyBox, Dropbear, ALSA, SBC, hostapd, umdns and BlueZ still compile their requested customized subset. They are **not** interchangeable with binary APK trimming without verifying functional equivalence.
- Source-build dependencies are installed as feed recipes, not precompiled unconditionally. The canonical 8eb72f8 builder used this distinction.
- This is a code-path and Makefile audit, **not evidence that all 43 packages pass compilation or runtime tests**.
