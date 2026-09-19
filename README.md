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

Release-family-specific AudioWRT compatibility deltas may live under `releases/<major.minor>/`, but those files may contain only AudioWRT overrides. They must not copy OpenWrt source metadata or OpenWrt-owned patches.

Current source-derived userspace packages are:

- `audiowrt-busybox` -> OpenWrt `busybox`;
- `audiowrt-minimal-alsa` -> OpenWrt packages feed `alsa-lib`;
- `audiowrt-minimal-mbedtls` -> OpenWrt `mbedtls`;
- `audiowrt-dropbear` -> OpenWrt `dropbear`;
- `audiowrt-wpad` -> OpenWrt `hostapd` source, linked as one multicall `hostapd` + `wpa_supplicant` binary;
- `audiowrt-umdns` -> OpenWrt `umdns`;
- `audiowrt-sbc` -> OpenWrt packages feed `sbc`;
- `audiowrt-bluez` -> OpenWrt packages feed `bluez`.

Not every AudioWRT package that customizes behavior should rebuild upstream source. If the AudioWRT delta is only runtime policy/configuration, the exact official release binary must be reused instead. This avoids rebuilding OpenWrt dependency graphs that already exist as release packages.

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

## Responsibility boundary

Reusable packages in this feed provide capabilities. They do not decide that an OpenWrt device should become an AudioWRT appliance.

Audio capabilities include USB DAC output management, UPnP/DLNA rendering, MPD playback, AirPlay, Spotify Connect, Bluetooth A2DP output, extension management and the reusable AudioWRT LuCI audio UI.

The reusable `audiowrt-wifi-client` capability can scan and configure Wi-Fi station mode and a temporary setup AP, but it is inert after installation until an explicit command or LuCI action enables it. The AudioWRT distribution owns the policy that activates this capability during first-boot provisioning.

Distribution behavior such as first-boot provisioning, client-only appliance defaults and guided USB extroot management is packaged here. Profile selection and firmware policy remain in the `audiowrt` repository.

## Packages

### `audiowrt-audio`

Common reusable audio state and helper CLI. The device/audio name is derived from OpenWrt's canonical `system.hostname`; AudioWRT does not keep a duplicate hostname in its own UCI config.

### `audiowrt-usb-audio`

Detects the first USB Audio Class playback device, creates the ALSA `default` output and reacts to USB hotplug. Minimal builds use `audiowrt-minimal-alsa`; standard builds use the normal OpenWrt ALSA package.

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

`audiowrt-bluez`, `audiowrt-sbc` and the minimal Bluetooth kmod package follow the exact selected OpenWrt release. `bluez-alsa` remains AudioWRT-owned because it has no canonical OpenWrt package recipe in the supported feed set. `audiowrt-bluetooth` provides the AudioWRT integration/service layer.

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
