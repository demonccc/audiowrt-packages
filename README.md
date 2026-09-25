# AudioWRT Packages

Reusable OpenWrt packages and LuCI applications used by AudioWRT.

This repository is the single catalog of every package maintained by AudioWRT. It includes reusable capabilities, distribution packages and constrained-runtime variants. Installing a package provides capability; the [`demonccc/audiowrt`](https://github.com/demonccc/audiowrt) distribution selects packages through its `minimal` and `standard` runtime groups.

## OpenWrt-derived package contract

AudioWRT does **not** fork OpenWrt package recipes by pinning a separate upstream version. If a package already exists in OpenWrt and AudioWRT really needs to rebuild that source, the AudioWRT replacement derives from the canonical recipe of the **selected OpenWrt release**.

For a release build, the official SDK/build context is authoritative. Core OpenWrt recipes are taken from the SDK's existing `$(TOPDIR)/package` tree; external recipes are taken from the exact release-pinned feeds such as `$(TOPDIR)/feeds/packages`. AudioWRT must **never materialize a second `base` package tree** merely to derive a package. Doing so duplicates Kconfig package symbols and can cause unrelated OpenWrt packages to enter a selective source build.

A source-derived AudioWRT package inherits from that exact recipe:

- upstream version/source/hash or git revision;
- OpenWrt build flags and hardening metadata;
- the complete OpenWrt patch set for that release;
- canonical package files that are part of the source recipe;
- the selected SDK target/subtarget/toolchain and architecture.

AudioWRT stores only the delta. Source patches owned by AudioWRT use the `9xx-*` namespace. If OpenWrt 24.10 and 25.12 use different upstream versions or patches, each AudioWRT build automatically inherits the version and patch set from the selected release instead of carrying parallel copies in this repository.

The helper is implemented by `include/audiowrt-openwrt-derived.mk` and `scripts/prepare-openwrt-derived.py`. Existing declarations may use the logical `feeds/base/...` location for a core package, but the helper resolves it to the already-present SDK/source-tree `package/...` recipe and never runs `scripts/feeds update base` itself.

## Package versioning policy

AudioWRT-owned packages use our semantic version, with the OpenWrt package
release fixed at `1` for the first packaging release:

- bug fix: `1.0.1`, then `1.0.2`, `1.0.3`, ...;
- backward-compatible feature: `1.1.0`, then `1.2.0`, ...;
- incompatible redesign: `2.0.0`.

The package release is not used as a second patch counter. This keeps an APK
such as `audiowrt-provisioning-1.0.3-r1` unambiguous: `1.0.3` is our package
revision and `r1` is the initial OpenWrt packaging record.

Packages that compile or repackage upstream code keep the upstream
`PKG_VERSION` inherited from, or declared for, that source. Their AudioWRT
delta is represented by the package name and recipe/patch provenance; the first
AudioWRT packaging revision starts at `PKG_RELEASE:=1`; packaging fixes increment
that release while preserving the upstream source version.
For example, the trimmed ALSA, BlueZ and wpad packages must remain traceable
to the selected OpenWrt source/kernel release instead of being relabeled as
an invented `1.0.x` source version. `audiowrt-wpad` inherits the exact
hostapd/wpa_supplicant source version and OpenWrt patches, then applies the
AudioWRT multicall and feature-selection delta.

Release-family-specific AudioWRT compatibility deltas may live under `releases/<major.minor>/`, but those files may contain only AudioWRT overrides. They must not copy OpenWrt source metadata or OpenWrt-owned patches.

Current source-derived userspace packages are:

- `audiowrt-busybox` -> OpenWrt `busybox`;
- `libaudiowrt-alsa-minimal` -> OpenWrt packages feed `alsa-lib`;
- `audiowrt-wpad` -> OpenWrt `hostapd` source, linked as one multicall `hostapd` + `wpa_supplicant` binary;
- `audiowrt-umdns` -> OpenWrt `umdns`;
- `audiowrt-sbc` -> OpenWrt packages feed `sbc`, stripped to the runtime library only;
- `audiowrt-bluez` -> OpenWrt packages feed `bluez`.

Not every AudioWRT package that customizes behavior should rebuild upstream source. If the AudioWRT delta is only runtime policy/configuration, the exact official release binary must be reused instead. This avoids rebuilding OpenWrt dependency graphs that already exist as release packages. TLS is intentionally kept on the official OpenWrt `libmbedtls` runtime; AudioWRT does not replace or trim it.

`audiowrt-wpad` is deliberately source-derived because AudioWRT changes the compiled feature set. It uses the exact hostap source and OpenWrt patch set from the selected release, builds a single multicall ELF, and exposes it through `/usr/sbin/hostapd` and `/usr/sbin/wpa_supplicant`. The station side keeps only WPA2/WPA3 Personal + PMF; the AP side is only the temporary open provisioning AP.

`audiowrt-minimal-upmpdcli` follows the same binary-reuse rule. It depends on the exact OpenWrt `upmpdcli` and `mpd-mini` release packages and only applies the AudioWRT renderer runtime profile: OpenHome disabled, MPD on loopback and a constrained FLAC/MP3 protocol advertisement. It is deliberately built with `NO_DEPS=1`; it must never cause MPD, libupnpp or their dependency graphs to be rebuilt.

Kernel replacements use a binary-derived strategy instead of rebuilding the kernel. `audiowrt-kmod-bluetooth`, `kmod-audiowrt-sound-core` and `kmod-audiowrt-usb-audio` repackage modules downloaded from the exact selected OpenWrt release/target and therefore keep the matching kernel ABI, target and architecture.

Packages for which OpenWrt has no canonical recipe remain AudioWRT-owned source packages. Today this includes `bluez-alsa` and `librespot`. They still compile with the selected OpenWrt SDK, target/subtarget and toolchain, but there is no OpenWrt recipe or OpenWrt patch set to inherit.

`tests/test-openwrt-derived-packages.sh` enforces the provenance contract: source-derived recipes cannot pin their own upstream source identity, copied OpenWrt patches are rejected, the helper is forbidden from materializing the base feed, and the minimal UPnP renderer is kept on the release-binary path.

## Selective source-build boundary

The distribution must not treat every selected runtime package as source-build intent.

- File-only packages, selectors and runtime profiles are built with `NO_DEPS=1`.
- Unchanged OpenWrt runtime packages come from the official release repositories and are installed by ImageBuilder.
- Only packages whose AudioWRT delta really changes the compiled binary may enter the source-build set.
- Adding a package to the source-build set is an explicit opt-in to compiling its required build/link dependency closure.
- A package must not be placed in that set merely because it references an upstream project.

This boundary is particularly important on constrained-device builds: selecting an AudioWRT runtime capability must not silently turn the SDK step into a broad OpenWrt source build.

## Package naming convention

AudioWRT-owned packages are named after the artifact they primarily install:

- `libaudiowrt-*` for shared userspace libraries;
- `audiowrt-player-*` for playback implementations;
- `audiowrt-*` for services, applications and helpers;
- `luci-app-audiowrt-*` for LuCI applications;
- `kmod-audiowrt-*` for kernel-module packages.

A package is not renamed to `libaudiowrt-*` merely because it contains a plugin `.so`; the prefix is reserved for packages whose primary runtime artifact is a reusable shared library.

## Runtime device identity

`audiowrt-identity` runs at boot (S11) and atomically creates
`/tmp/audiowrt/uuid`. It uses a fixed AudioWRT UUIDv8 prefix and a permanent
onboard MAC, preferring Ethernet and falling back to an onboard Wi-Fi PHY.
Virtual/random interface addresses and USB adapters are excluded. The UUID
is independent of hostname and boot time; it is never persisted. Devices
with identical permanent MACs will have identical UUIDs.

Consumers read this file instead of generating or saving individual UUIDs.
The renderer depends on this package and fails to initialize if the file is
missing or invalid. Legacy renderer UCI UUID values are ignored, without
rewriting existing configuration. Installing on an already running device
requires starting `audiowrt-identity` before starting the renderer.

## Playback registry

AudioWRT keeps playback capabilities separate from module preferences:

- `/etc/config/audiowrt-runtime-codecs` is the shared codec catalog. Player packages create missing codec sections and merge MIME types and file extensions when they are installed.
- `/etc/config/audiowrt-runtime-players` is the shared player catalog. Player packages register their executable and the codecs they implement.
- Consumer modules such as the DLNA renderer read both catalogs but keep their preferred/default player choices in their own UCI package, for example `/etc/config/audiowrt-dlna`.
- Installing or removing a player never chooses a default for DLNA or another consumer. If no module-specific preference is configured, the consumer falls back to any available compatible player.
- Legacy catalog files are ignored without flash migration. Both new catalog paths are immutable symlinks to `/tmp/audiowrt/registry`. Installed manifests under `/usr/share/audiowrt/players` are the single source of capabilities. The S12 initializer and package hooks rebuild only the RAM view. Playback never rewrites it.

`/usr/libexec/audiowrt-playback-registry` rebuilds the derived RAM catalogs. 
## Responsibility boundary

Reusable packages in this feed provide capabilities. They do not decide that an OpenWrt device should become an AudioWRT appliance.

Audio capabilities include USB DAC output management, UPnP/DLNA rendering, MPD playback, AirPlay, Spotify Connect, Bluetooth A2DP output, extension management and the reusable AudioWRT LuCI audio UI.

The reusable `audiowrt-wifi-client` capability can scan and configure Wi-Fi station mode and a temporary setup AP, but it is inert after installation until an explicit command or LuCI action enables it. The AudioWRT distribution owns the policy that activates this capability during first-boot provisioning.

Distribution behavior such as first-boot provisioning, client-only appliance defaults is packaged here. Profile selection and firmware policy remain in the `audiowrt` repository.

## Packages

### `audiowrt-audio`

Common reusable audio state and helper CLI. The device/audio name is derived from OpenWrt's canonical `system.hostname`; AudioWRT does not keep a duplicate hostname in its own UCI config.

### `audiowrt-usb-audio`

Detects the first USB Audio Class playback device, creates the ALSA `default` output and reacts to USB hotplug. Minimal builds use `libaudiowrt-alsa-minimal`; standard builds use the normal OpenWrt ALSA package.

### `audiowrt-minimal-upmpdcli`

Configuration-only profile for the exact OpenWrt `upmpdcli` and `mpd-mini` binaries. It disables OpenHome, keeps MPD internal on loopback and replaces the renderer protocol advertisement with the constrained FLAC/MP3 profile. It contains no upstream source and is built with `NO_DEPS=1`.

### `audiowrt-extensions`

Runtime service manager using OpenWrt's package manager. The initial extension catalog contains MPD, AirPlay, Spotify and Bluetooth.

### `audiowrt-mpd`

Configures whichever package provides the `mpd` capability and keeps the daemon on `127.0.0.1:6600` for use as an internal playback backend. The constrained firmware selects the official OpenWrt `mpd-mini` package.

### `audiowrt-airplay`

Installs `shairport-sync-mini`, uses the current OpenWrt hostname as the AudioWRT audio name and sends playback to ALSA `default`.

### `librespot` + `audiowrt-spotify`

Packages librespot with the selected OpenWrt Rust toolchain, ALSA backend, rustls and pure-Rust mDNS. Spotify Premium is required by librespot.

### Bluetooth stack

`audiowrt-bluez`, `audiowrt-sbc` and the minimal Bluetooth kmod package follow the exact selected OpenWrt release. AudioWRT reuses the official OpenWrt `bluez-libs` package, while `audiowrt-sbc` derives from the exact OpenWrt SBC recipe but disables the tester and installs only `libsbc`, saving about 14.7 KiB in the constrained image. `bluez-alsa` remains AudioWRT-owned because it has no canonical OpenWrt package recipe in the supported feed set. `audiowrt-bluetooth` provides the AudioWRT integration/service layer.

### `audiowrt-wifi-client`

Reusable Wi-Fi client backend. It can:

- enumerate and scan every OpenWrt Wi-Fi radio;
- create/update the `audiowrt_wifi` DHCP client interface;
- create/update the `audiowrt_client` STA interface on the selected radio;
- create/stop a temporary `audiowrt_setup` AP when explicitly requested;
- keep mDNS bound to the normal LAN, AudioWRT Wi-Fi client and setup networks.

Installing the package does **not** alter OpenWrt networking. All mutations require an explicit CLI or LuCI action.

### `luci-app-audiowrt-wifi-client`

Adds **Network -> Wi-Fi Client**. It scans all radios and lets the user explicitly select and connect to a network. It is suitable for ordinary OpenWrt installations as well as the AudioWRT distribution.

### `luci-app-audiowrt`

Reusable audio-only LuCI interface for AudioWRT outputs and extensions.

## Use as an OpenWrt feed

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git
```

Then:

```sh
./scripts/feeds update audiowrt
./scripts/feeds install -a -p audiowrt
```

Source-derived packages expect their canonical OpenWrt recipe to be available in the selected build context. Core recipes come from the existing `package/` tree; packages-feed recipes require the exact selected `packages` feed checkout. The package helper never updates the base feed on its own.

Installing packages from the feed does not turn an OpenWrt router into the AudioWRT distribution.

## Architecture

File-only packages are marked `PKGARCH:=all` where possible. Native packages are compiled by the selected OpenWrt SDK and are target-architecture specific. Package architecture is independent from release compatibility: release compatibility comes from deriving canonical OpenWrt packages from the selected release context rather than pinning one OpenWrt version in this feed.

## GitHub Actions policy

GitHub Actions are manual-only (`workflow_dispatch`). Pushes and pull requests do not consume hosted-runner time automatically.

## License

AudioWRT-owned package code is GPL-2.0-only unless stated otherwise. LuCI components use Apache-2.0. Third-party sources retain their upstream licenses.

## Runtime persistence policy

Boot, network changes, discovery, playback and hotplug do not save operational
state. Only explicit configuration actions persist user settings. There are no
AudioWRT `uci-defaults` migrations or persistent first-run flags.

Wi-Fi **Connect** stages a test in RAM; **Save** persists the tested station
profile. On single-radio hardware provisioning restores the setup AP after a
successful test so the user can reconnect and press Save. Reboot without Save
returns to the previously saved configuration. Hostname and root password in the
wizard are also saved only by Save.

Provisioning waits at most 45 seconds for Ethernet or managed Wi-Fi link plus a
global IP address, including static addresses. An AP or saved-but-disconnected
Wi-Fi profile does not suppress setup. The controller owns a direct hostapd and
udhcpd pair, their PIDs/configs/leases/logs under `/tmp/audiowrt/setup`, and the
`awsetup` interface. It releases the selected PHY from netifd before creating
that interface. A single procd supervisor performs final handoff and cleanup.
Hardware association, ACS and recovery still require validation on target radios.

`audiowrt-config` isolates explicit saves using private UCI package names and
persistent snapshots. It neither includes nor deletes unrelated staged deltas.
Equivalent settings cause no rewrite; a changed snapshot aborts the save. Saves
of multiple UCI files are per-file atomic, not a filesystem-wide transaction.

Audio outputs share `/tmp/audiowrt/audio.state` and generate the optional ALSA
route only when needed. `/etc/asound.conf` is an immutable symlink to that RAM
route; no empty file is created at boot. Output changes restart only running,
enabled engines, and repeated selection is a no-op. Bluetooth device/status
queries do not start services. Pairing is volatile until the explicit Save action.
The renderer runtime directory is fixed under `/tmp`, and its default friendly
name follows the hostname. AirPlay uses the hostname token; Spotify derives its
name at startup unless the user supplied an override.

Storage/extroot uses official OpenWrt packages; the AudioWRT storage CLI and LuCI
module have been removed. Optional MPD/AirPlay/Spotify integrations configure on
explicit live installation or `audiowrt-extensions configure <name>`, never on
first boot. The AudioWRT builder bakes their shared defaults into images selecting those
integrations, instead of using a first-boot migration.

Quick checks: `bash tests/test-flash-write-policy.sh`,
`bash tests/test-device-identity.sh`, and
`UCI_BIN=/path/to/uci python3 tests/test-runtime-behavior.py`.
The behavioral tests use real UCI with isolated config directories and simulated
hardware; they do not perform DHCP waits or require access to a router.
