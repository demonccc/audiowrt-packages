#!/usr/bin/env python3
"""Fast behavioral checks: real UCI, fake hardware, no router or flash access."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
UCI = os.environ.get("UCI_BIN") or shutil.which("uci")


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="audiowrt-test-")
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        for name in ("config", "delta", "bin", "run"):
            (self.root / name).mkdir()
        self.env = dict(os.environ, ROOT=str(self.root), SAVE_ROOT=str(self.root / "config"))
        self.env["PATH"] = str(self.root / "bin") + ":" + self.env["PATH"]
        if UCI:
            (self.root / "bin/uci").symlink_to(Path(UCI).resolve())
        self.helper = self.copy("audiowrt-config/files/config-save", "config-save")

    def copy(self, source, dest):
        text = (REPO / source).read_text().replace("/tmp/audiowrt", str(self.root / "run"))
        text = text.replace("/usr/libexec/audiowrt/config-save", str(self.root / "config-save"))
        text = text.replace("/usr/libexec/audiowrt/wifi-runtime", str(self.root / "wifi-runtime"))
        target = self.root / dest
        target.write_text(text)
        return target

    def shell(self, body, success=True):
        result = subprocess.run(["sh", "-eu", "-c", body], env=self.env, text=True,
                                capture_output=True, timeout=15)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    @unittest.skipUnless(UCI, "UCI_BIN is required for real UCI tests")
    def test_save_ignores_foreign_deltas_and_repeated_save_is_noop(self):
        # Unique package permits testing UCI's REAL default /tmp/.uci safely.
        package = "awtest_" + str(os.getpid())
        config = self.root / "config" / package
        config.write_text("config test 'main'\n option own 'old'\n option other 'saved'\n")
        pending = Path("/tmp/.uci") / package
        self.addCleanup(lambda: pending.unlink(missing_ok=True))
        self.shell(f"uci -c '$ROOT/config' get x", success=False)  # sanity: errors propagate
        self.shell(f'uci -c "$ROOT/config" set {package}.main.other=temporary')
        action = f'. "{self.helper}"; save_begin {package}; save_uci set {package}.main.own=new; save_finish'
        self.shell(action)
        self.assertIn("'new'", config.read_text())
        self.assertIn("'saved'", config.read_text())
        self.assertNotIn("temporary", config.read_text())
        self.assertTrue(pending.exists(), "Saving must not discard somebody else's deltas")
        before = config.stat()
        self.shell(action)
        after = config.stat()
        self.assertEqual((before.st_ino, before.st_mtime_ns), (after.st_ino, after.st_mtime_ns))

    @unittest.skipUnless(UCI, "UCI_BIN is required for real UCI tests")
    def test_concurrent_persistent_change_aborts_save(self):
        (self.root / "config/test").write_text("config test 'main'\n option value 'old'\n")
        self.shell(f'. "{self.helper}"; save_begin test; save_uci set test.main.value=new; '
                   'printf "# another writer\\n" >> "$ROOT/config/test"; save_finish', success=False)
        self.assertNotIn("new", (self.root / "config/test").read_text())

    @unittest.skipUnless(UCI, "UCI_BIN is required for real UCI tests")
    def test_connect_does_not_save_and_save_only_persists_client(self):
        self.copy("audiowrt-wifi-client/files/audiowrt-wifi-runtime", "wifi-runtime")
        wifi = self.copy("audiowrt-wifi-client/files/audiowrt-wifi-client", "wifi")
        wifi.write_text(wifi.read_text().split('\ncase "${1:-}"')[0])
        (self.root / "config/wireless").write_text("config wifi-device 'radio0'\n option disabled '1'\n option channel 'auto'\n")
        (self.root / "config/network").write_text("config interface 'lan'\n option proto 'dhcp'\n")
        originals = {p.name: p.read_bytes() for p in (self.root / "config").iterdir()}
        prefix = f'. "{wifi}"; uci() {{ command uci -c "$ROOT/config" -t "$ROOT/delta" "$@"; }}; wifi() {{ :; }}; mdns_sync() {{ :; }}; '
        self.shell(prefix + 'uci set network.lan.proto=static; uci set wireless.radio0.channel=11; '
                   "connect_wifi radio0 'Test Network' psk2 'testpass123'")
        for name, contents in originals.items():
            self.assertEqual((self.root / "config" / name).read_bytes(), contents)
        self.shell(prefix + 'audiowrt_client_up() { return 1; }; commit_wifi_client', success=False)
        self.shell(prefix + 'audiowrt_client_up() { return 0; }; commit_wifi_client')
        self.assertIn("'dhcp'", (self.root / "config/network").read_text())
        self.assertNotIn("'static'", (self.root / "config/network").read_text())
        saved = (self.root / "config/wireless").read_text()
        self.assertIn("Test Network", saved)
        self.assertIn("'auto'", saved)
        self.assertNotIn("'11'", saved)
        self.assertNotIn("audiowrt_setup", saved)

    @unittest.skipUnless(UCI, "UCI_BIN is required for real UCI tests")
    def test_invalid_static_ip_does_not_change_live_deltas(self):
        self.copy("audiowrt-wifi-client/files/audiowrt-wifi-runtime", "wifi-runtime")
        wifi = self.copy("audiowrt-wifi-client/files/audiowrt-wifi-client", "wifi")
        wifi.write_text(wifi.read_text().split('\ncase "${1:-}"')[0])
        (self.root / "config/wireless").write_text("config wifi-device 'radio0'\n option disabled '1'\n")
        (self.root / "config/network").write_text("config interface 'lan'\n option proto 'dhcp'\n")
        self.shell(f'. "{wifi}"; uci() {{ command uci -c "$ROOT/config" -t "$ROOT/delta" "$@"; }}; '
                   "connect_wifi radio0 test none '' '' static 999.1.1.1 255.255.255.0 10.0.0.1", success=False)
        self.assertEqual(list((self.root / "delta").iterdir()), [])

    def test_audio_repeated_selection_preserves_runtime_files(self):
        helper = self.copy("audiowrt-audio/files/audio-runtime", "audio-runtime")
        action = f'. "{helper}"; audio_state usb 1 0 0 "" "" ""; printf "pcm.test {{ type hw }}\\n" | audio_asound; restart_engines'
        self.shell(action)
        state = self.root / "run/audio.state"
        route = self.root / "run/asound.conf"
        before = (state.stat().st_ino, route.stat().st_ino)
        self.shell(action)
        self.assertEqual(before, (state.stat().st_ino, route.stat().st_ino))
        self.assertEqual(list((self.root / "config").iterdir()), [])

    def test_audio_does_not_start_disabled_engine(self):
        helper = self.copy("audiowrt-audio/files/audio-runtime", "audio-runtime")
        services = self.root / "services"
        services.mkdir()
        mpd = services / "mpd"
        mpd.write_text('#!/bin/sh\ncase "$1" in enabled) exit 1;; restart) touch "$ROOT/restarted";; esac\n')
        mpd.chmod(0o755)
        helper.write_text(helper.read_text().replace("/etc/init.d", str(services)))
        self.shell(f'. "{helper}"; audio_state usb 1 0 0 "" "" ""; restart_engines')
        self.assertFalse((self.root / "restarted").exists())

    @unittest.skipUnless(UCI, "UCI_BIN is required for real UCI tests")
    def test_renderer_save_validates_before_writing(self):
        script = self.copy("audiowrt-dlna/files/save-renderer", "save-renderer")
        script.write_text(script.read_text().replace("/etc/init.d/audiowrt-renderer", "true"))
        config = self.root / "config/audiowrt-dlna"
        original = "config renderer 'main'\n option port '49152'\n option volume '100'\n"
        config.write_text(original)
        self.shell(f'sh "{script}" volume 25 port 99999', success=False)
        self.assertEqual(config.read_text(), original)
        self.shell(f'sh "{script}" volume 25')
        self.assertIn("'25'", config.read_text())
        before = config.stat().st_mtime_ns
        self.shell(f'sh "{script}" volume 25')
        self.assertEqual(config.stat().st_mtime_ns, before)

    @unittest.skipUnless(UCI, "UCI_BIN is required for real UCI tests")
    def test_module_defaults_preserve_explicit_name_and_skip_rewrite(self):
        script = self.copy("audiowrt-config/files/configure-settings", "configure-settings")
        config = self.root / "config/shairport-sync"
        config.write_text("config shairport-sync 'shairport_sync'\n option name 'Living Room'\n option enabled '0'\n")
        template = REPO / "audiowrt-airplay/files/airplay.settings"
        action = f'sh "{script}" shairport-sync shairport_sync "{template}"'
        self.shell(action)
        self.assertIn("'Living Room'", config.read_text())
        self.assertIn("enabled '1'", config.read_text())
        before = config.stat().st_mtime_ns
        self.shell(action)
        self.assertEqual(before, config.stat().st_mtime_ns)

    def test_connectivity_requires_link_and_ip_and_excludes_access_points(self):
        runtime = self.copy("audiowrt-wifi-client/files/audiowrt-wifi-runtime", "wifi-runtime")
        net = self.root / "net"
        for name in ("eth0", "wlan0"):
            (net / name).mkdir(parents=True)
            (net / name / "type").write_text("1\n")
            (net / name / "carrier").write_text("1\n")
        (net / "eth0/device").mkdir()
        (net / "wlan0/phy80211").mkdir()
        runtime.write_text(runtime.read_text().replace("/sys/class/net", str(net)))
        prefix = f'. "{runtime}"; ' + r'''
            ubus() { if [ "$1" = list ]; then echo network.interface.lan; else echo '{}'; fi; }
            jsonfilter() { cat >/dev/null; case "$*" in *up*) echo true ;; *) echo "$DEV" ;; esac; }
            ip() { [ "$HAS_IP" = 1 ] && echo "1: $DEV inet 192.168.1.2/24 scope global"; }
            iw() { case "$*" in *info*) echo "type $MODE" ;; *link*) echo 'Connected to 00:11:22:33:44:55';; esac; }
        '''
        self.shell(prefix + 'DEV=eth0; HAS_IP=1; MODE=managed; audiowrt_connected')
        (net / "eth0/carrier").write_text("0\n")
        self.shell(prefix + 'DEV=eth0; HAS_IP=1; MODE=managed; audiowrt_connected', success=False)
        self.shell(prefix + 'DEV=wlan0; HAS_IP=1; MODE=AP; audiowrt_connected', success=False)
        self.shell(prefix + 'DEV=wlan0; HAS_IP=0; MODE=managed; audiowrt_connected', success=False)
        self.shell(prefix + 'DEV=wlan0; HAS_IP=1; MODE=managed; audiowrt_connected')

    def test_failed_hostapd_is_reported_and_owned_interface_is_cleaned(self):
        runtime = self.copy("audiowrt-wifi-client/files/audiowrt-wifi-runtime", "wifi-runtime")
        (self.root / "phy/phy0").mkdir(parents=True)
        ap = self.copy("audiowrt-provisioning/files/setup-ap", "setup-ap")
        ap.write_text(ap.read_text().replace("/sys/class/ieee80211", str(self.root / "phy"))
                      .replace("/usr/sbin/audiowrt-wifi-client mdns-sync", ":"))
        for command, body in {
            "uci": "case \"$*\" in *wireless.radio0.phy*) echo phy0;; *wireless.radio0.band*) echo 2g;; *wireless.radio0.path*|*country*) exit 1;; *) echo wifi-device;; esac",
            "iw": 'echo "$*" >> "$ROOT/iw.log"',
            "wifi": ":",
            "ip": ":",
            "hostapd": "echo 'driver initialization failed'; exit 7",
            "udhcpd": 'touch "$ROOT/dhcp-started"',
        }.items():
            path = self.root / "bin" / command
            if path.is_symlink():
                path.unlink()
            path.write_text("#!/bin/sh\n" + body + "\n")
            path.chmod(0o755)
        result = self.shell(f'sh "{ap}" start radio0 Test', success=False)
        self.assertIn("driver initialization failed", result.stderr)
        self.assertIn("dev awsetup del", (self.root / "iw.log").read_text())
        self.assertFalse((self.root / "dhcp-started").exists())
        self.assertFalse((self.root / "run/setup").exists())

    @unittest.skipUnless(UCI, "UCI_BIN is required for real UCI tests")
    def test_registry_merges_shared_codec_and_handles_removal_in_ram(self):
        registry = self.copy("libaudiowrt-player/files/audiowrt-playback-registry", "registry")
        manifests = self.root / "manifests"
        manifests.mkdir()
        for codec in ("m4a", "ffmpeg"):
            shutil.copy(REPO / f"audiowrt-player-{codec}/files/{codec}.manifest", manifests)
        registry.write_text(registry.read_text().replace("/usr/share/audiowrt/players", str(manifests)))
        self.shell(f'sh "{registry}" rebuild')
        players = self.root / "run/registry/audiowrt-players"
        self.assertIn("native_m4a", players.read_text())
        self.assertIn("ffmpeg_audio", players.read_text())
        self.shell(f'sh "{registry}" exclude ffmpeg')
        self.assertNotIn("ffmpeg_audio", players.read_text())
        self.assertIn("native_m4a", players.read_text())
        self.assertEqual(list((self.root / "config").iterdir()), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
