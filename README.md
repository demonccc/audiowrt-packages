# AudioWRT Packages

Reusable OpenWrt packages and LuCI applications used by AudioWRT.

This repository is the single catalog of every package maintained by AudioWRT. It includes reusable capabilities, distribution packages and constrained-runtime variants. Installing a package provides capability; the [`demonccc/audiowrt`](https://github.com/demonccc/audiowrt) distribution selects packages through its `minimal` and `standard` runtime groups.

## OpenWrt-derived package contract

AudioWRT does **not** fork OpenWrt package recipes by pinning a separate upstream version. If a package already exists in OpenWrt, an AudioWRT replacement must derive from the canonical recipe of the **selected OpenWrt release**.

For a release build, the official SDK `feeds.conf.default` is authoritative. The builder updates the exact pinned `base` and `packages` feed revisions from that SDK. A derived AudioWRT package then inherits from that exact recipe:

- upstream version/source/hash or git revision;
- OpenWrt build flags and hardening metadata;
- the complete OpenWrt patch set for that release;
- canonical package files that are part of the source recipe;
- the selected SDK target/subtarget/toolchain and architecture.

AudioWRT stores only the delta. Source patches owned by AudioWRT use the `9xx-*` namespace. If OpenWrt 24.10 and 25.12 use different upstream versions or patches, each AudioWRT build automatically inherits the version and patch set from the selected release instead of carrying parallel copies in this repository.

The helper is implemented by `include/audiowrt-openwrt-derived.mk` and `scripts/prepare-openwrt-derived.py`. The package recipe declares its canonical source, for example:

```make
AUDIOWRT_DERIVED_NAME:=audiowrt-dropbear
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/base/network/services/dropbear/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk
```

Release-family-specific AudioWRT compatibility deltas may live under `releases/<major.minor>/`, but those files may contain only AudioWRT overrides. They must not copy OpenWrt source metadata or OpenWrt-owned patches.

Current derived userspace packages are:

- `audiowrt-busybox` -> OpenWrt `busybox`;
- `audiowrt-minimal-alsa` -> OpenWrt packages feed `alsa-lib`;
- `audiowrt-minimal-mbedtls` -> OpenWrt `mbedtls`;
- `audiowrt-dropbear` -> OpenWrt `dropbear`;
- `audiowrt-minidlna` -> OpenWrt packages feed `minidlna`;
- `audiowrt-umdns` -> OpenWrt `umdns`;
- `audiowrt-sbc` -> OpenWrt packages feed `sbc`;
- `audiowrt-bluez` -> OpenWrt packages feed `bluez`.

`audiowrt-wpa-supplicant` is a selector rather than a source fork: it depends on the exact `wpa-supplicant-mbedtls` package shipped by the selected OpenWrt SDK/release.

Kernel replacements use a binary-derived strategy instead of rebuilding the kernel. `audiowrt-kmod-bluetooth`, `kmod-audiowrt-sound-core` and `kmod-audiowrt-usb-audio` repackage modules downloaded from the exact selected OpenWrt release/target and therefore keep the matching kernel ABI, target and architecture.

Packages for which OpenWrt has no canonical recipe remain AudioWRT-owned source packages. Today this includes `bluez-alsa` and `librespot`. They still compile with the selected OpenWrt SDK, target/subtarget and toolchain, but there is no OpenWrt recipe or OpenWrt patch set to inherit.

`tests/test-openwrt-derived-packages.sh` enforces the contract: derived recipes cannot pin their own upstream source identity and copied OpenWrt patches are rejected.

## Responsibility boundary

Reusable packages in this feed provide capabilities. They do not decide that an OpenWrt device should become an AudioWRT appliance.

Audio capabilities include USB DAC output management, MPD/local music, AirPlay, Spotify Connect, Bluetooth A2DP output, extension management and the reusable AudioWRT LuCI audio UI.

The reusable `audiowrt-wifi-client` capability can scan and configure Wi-Fi station mode and a temporary setup AP, but it is inert after installation until an explicit command or LuCI action enables it. The AudioWRT distribution owns the policy that activates this capability during first-boot provisioning.

Distribution behavior such as first-boot provisioning, client-only appliance defaults and guided USB extroot management is packaged here. Profile selection and firmware policy remain in the `audiowrt` repository.

## Packages

### `audiowrt-audio`

Common reusable audio state and helper CLI. The device/audio name is derived from OpenWrt's canonical `system.hostname`; AudioWRT does not keep a duplicate hostname in its own UCI config.

### `audiowrt-usb-audio`

Detects the first USB Audio Class playback device, creates the ALSA `default` output and reacts to USB hotplug. Minimal builds use `audiowrt-minimal-alsa`; standard builds use the normal OpenWrt ALSA package.

### `audiowrt-extensions`

Runtime service manager using OpenWrt's package manager. The initial extension catalog contains MPD, AirPlay, Spotify and Bluetooth.

### `audiowrt-mpd`

Installs `mpd-mini` and configures local/HTTP playback through ALSA `default`.

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

Derived packages expect the canonical OpenWrt `base`/`packages` feeds for the build tree to be present. The AudioWRT distribution builder prepares those feeds from the selected SDK automatically.

Installing packages from the feed does not turn an OpenWrt router into the AudioWRT distribution.

## Architecture

File-only packages are marked `PKGARCH:=all` where possible. Native packages are compiled by the selected OpenWrt SDK and are target-architecture specific. Package architecture is independent from release compatibility: release compatibility comes from deriving canonical OpenWrt packages from the selected release context rather than pinning one OpenWrt version in this feed.

## GitHub Actions policy

GitHub Actions are manual-only (`workflow_dispatch`). Pushes and pull requests do not consume hosted-runner time automatically.

## License

AudioWRT-owned package code is GPL-2.0-only unless stated otherwise. LuCI components use Apache-2.0. Third-party sources retain their upstream licenses.
