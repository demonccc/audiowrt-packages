#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "flash-write policy failed: $*" >&2
    exit 1
}

audio="$repo_root/audiowrt-audio/files/audiowrt-audio"
usb="$repo_root/audiowrt-usb-audio/files/select-audio-output"
usb_hotplug="$repo_root/audiowrt-usb-audio/files/audiowrt-audio.hotplug"
bluetooth="$repo_root/audiowrt-bluetooth/files/audiowrt-bluetooth"
renderer_init="$repo_root/audiowrt-dlna/files/audiowrt-dlna.init"
renderer_src="$repo_root/audiowrt-dlna/src"
provision="$repo_root/audiowrt-provisioning/files/audiowrt-provision"
provision_cgi="$repo_root/audiowrt-provisioning/files/audiowrt-provision.cgi"
provision_firstboot="$repo_root/audiowrt-provisioning/files/audiowrt-provisioning-firstboot"
audiowrtctl="$repo_root/audiowrt-provisioning/files/audiowrtctl"
status_cgi="$repo_root/audiowrt-provisioning/files/audiowrt-status.cgi"
core_config="$repo_root/audiowrt-core/files/audiowrt.config"
wifi="$repo_root/audiowrt-wifi-client/files/audiowrt-wifi-client"
registry="$repo_root/libaudiowrt-player/files/audiowrt-player-registry"
status_luci="$repo_root/luci-app-audiowrt/htdocs/luci-static/resources/view/status/include/90_audiowrt.js"

# High-frequency audio paths must only touch volatile storage.
for file in "$audio" "$usb" "$usb_hotplug"; do
    if grep -Eq 'uci[[:space:]].*commit|>[[:space:]]*/etc/|cp[[:space:]].*[[:space:]]/etc/|mv[[:space:]].*[[:space:]]/etc/' "$file"; then
        fail "high-frequency audio path writes persistent configuration: $file"
    fi
done

grep -Fq 'RUNTIME_DIR=/tmp/audiowrt' "$usb" || fail 'USB runtime is not rooted in /tmp'
grep -Fq 'RUNTIME_DIR=/tmp/audiowrt' "$bluetooth" || fail 'Bluetooth runtime is not rooted in /tmp'
grep -Fq '#define DEFAULT_RUNTIME_DIR "/var/run/audiowrt-dlna"' "$renderer_src/renderer-part-00.inc" ||
    fail 'renderer status is not rooted in /var/run'
if grep -q 'option runtime_dir' "$repo_root/audiowrt-dlna/files/audiowrt-dlna.config"; then
    fail 'renderer runtime directory must not be configurable to persistent storage'
fi
if grep -q 'strcmp(key, "runtime_dir")' "$renderer_src/renderer-part-01.inc"; then
    fail 'renderer still accepts a configurable runtime directory'
fi

# The Bluetooth watcher may persist only an explicit user Save.
commit_count="$(grep -c 'uci -q commit' "$bluetooth" || true)"
[[ "$commit_count" -eq 1 ]] || fail "Bluetooth contains $commit_count persistent commits; expected explicit Save only"
awk '
    /^save_device\(\)/ { in_save=1 }
    in_save && /uci -q commit/ { found=1 }
    /^restore_saved\(\)/ { in_save=0 }
    END { exit found ? 0 : 1 }
' "$bluetooth" || fail 'Bluetooth commit escaped the explicit save_device() action'

# Renderer identity is persistent, but only the one-time UUID initialization may commit.
renderer_commits="$(grep -c 'uci -q commit' "$renderer_init" || true)"
[[ "$renderer_commits" -eq 1 ]] || fail "renderer init contains unexpected persistent commits"

# Transient provisioning errors belong to tmpfs, never the persistent AudioWRT UCI config.
if grep -Rqs 'audiowrt\.main\.last_error' \
    "$repo_root"/audiowrt-* "$repo_root"/luci-app-* "$repo_root"/libaudiowrt-player 2>/dev/null; then
    fail 'transient provisioning last_error is still stored/read through persistent UCI'
fi
if grep -q 'option last_error' "$core_config"; then
    fail 'core UCI schema still declares transient last_error'
fi
for file in "$provision" "$audiowrtctl" "$status_cgi"; do
    grep -q 'provisioning.error' "$file" || fail "volatile provisioning error file missing from $file"
done

# Provisioning mode is derived from connectivity/runtime setup, never stored in
# the persistent AudioWRT UCI schema. Legacy keys may appear only in the
# first-install migration that deletes them.
if grep -Eq 'option (provisioning|provisioning_initialized)' "$core_config"; then
    fail 'core UCI schema still stores provisioning state'
fi
for file in "$provision" "$provision_cgi" "$audiowrtctl" "$status_cgi"; do
    if grep -q 'audiowrt\.main\.provisioning' "$file"; then
        fail "active provisioning path still uses persistent provisioning state: $file"
    fi
done
grep -q 'provisioning.done' "$provision" ||
    fail 'verified provisioning completion is not tracked in tmpfs'
grep -q 'provisioning.done' "$status_cgi" ||
    fail 'status does not wait for verified tmpfs completion before showing Done'

# External-overlay operation must not silently mirror every configuration change
# back to the internal flash. sync-core remains an explicit storage command only.
if grep -Rqs --exclude='audiowrt-storage' --exclude='*.md' --exclude='*.sh' \
    'audiowrt-storage sync-core' \
    "$repo_root"/audiowrt-* "$repo_root"/luci-app-* "$repo_root"/libaudiowrt-player 2>/dev/null; then
    fail 'another package automatically invokes internal-flash sync-core'
fi
if grep -q 'audiowrt-storage sync-core' "$provision" "$audiowrtctl"; then
    fail 'provisioning still auto-syncs configuration into the internal overlay'
fi
grep -q 'sync-core' "$repo_root/audiowrt-storage/files/audiowrt-storage" ||
    fail 'explicit storage sync-core command was accidentally removed'

# The setup AP is runtime-only. setup-start/setup-stop may stage UCI changes
# in tmpfs and reload netifd, but must never commit those setup sections.
setup_runtime="$(sed -n '/^setup_start()/,/^mdns_sync()/p' "$wifi")"
if printf '%s\n' "$setup_runtime" | grep -Eq 'uci -q commit (network|wireless)'; then
    fail 'setup-start/setup-stop persists runtime provisioning state'
fi
grep -Fq 'stage_setup_config "$radio" "$ssid" "$setup_ip"' "$wifi" ||
    fail 'setup-start does not stage runtime setup state'
grep -Fq 'AUDIOWRT_WIFI_PERSIST' "$wifi" ||
    fail 'Wi-Fi client cannot be tested without persistence'
grep -q '^commit_wifi_client()' "$wifi" ||
    fail 'verified Wi-Fi client has no isolated persistence path'
grep -Fq 'uci -q delete network.audiowrt_setup' "$wifi" ||
    fail 'client commit does not exclude runtime setup network'
grep -Fq 'uci -q delete wireless.audiowrt_setup' "$wifi" ||
    fail 'client commit does not exclude runtime setup AP'
grep -Fq 'stage_setup_config "$setup_radio"' "$wifi" ||
    fail 'setup AP is not re-staged after the verified client commit'

# Explicit disconnect remains persistent but repeated calls are idempotent.
grep -Fq "uci -q get wireless.audiowrt_client >/dev/null 2>&1 || return 0" "$wifi" ||
    fail 'Wi-Fi disconnect does not short-circuit when the client section is absent'
grep -Fq 'wireless.audiowrt_client.disabled 2>/dev/null || echo 0' "$wifi" ||
    fail 'Wi-Fi disconnect does not inspect the persisted disabled state'
grep -Fq " = '1' ] && return 0" "$wifi" ||
    fail 'Wi-Fi disconnect does not short-circuit when already disabled'

# Legacy umdns compatibility may persist the required network list once, but
# repeated mdns-sync calls must be no-op for flash when nothing changed.
grep -Fq '[ "$changed" -eq 0 ] || uci -q commit umdns' "$wifi" ||
    fail 'legacy mDNS fallback does not guard its flash commit with a change check'
if grep -q 'del_list umdns.@umdns\[0\].network' "$wifi"; then
    fail 'legacy mDNS sync still rewrites existing list entries every time'
fi

# Package registration is persistent configuration, but reinstalling the same
# player must not cause a no-op UCI commit.
grep -Fq 'if [ "$changed" -eq 1 ]; then' "$registry" ||
    fail 'player registry does not guard commits with a real-change check'

# Status surfaces must consume the runtime file/command, not resurrect the old
# UCI-backed audio state model.
grep -Fq '/usr/sbin/audiowrt-audio status' "$status_cgi" ||
    fail 'provisioning status CGI does not read volatile audio state'
grep -Fq "fs.exec('/usr/sbin/audiowrt-audio', [ 'status' ])" "$status_luci" ||
    fail 'LuCI status does not read volatile audio state'
if grep -Eq "uci\.get\('audiowrt-audio'.*(ready|device|output_type|last_error)" "$status_luci"; then
    fail 'LuCI status still reads runtime audio fields from UCI'
fi

echo 'Runtime flash-write policy passed.'
