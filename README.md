# AudioWRT Packages

Reusable OpenWrt packages, AudioWRT runtime components and LuCI applications used by the AudioWRT distribution.

This repository is a **single OpenWrt feed** organized by package provenance and ownership. The AudioWRT firmware builder lives in [`demonccc/audiowrt`](https://github.com/demonccc/audiowrt) and selects which packages belong in each firmware profile.

## Package families

The authoritative packaging contract is documented in [`docs/PACKAGING.md`](docs/PACKAGING.md).

```text
audiowrt-packages/
├── audiowrt/   # AudioWRT-owned code, integrations and UI
├── ported/     # upstream software without a canonical OpenWrt recipe
├── trimmed/    # canonical OpenWrt packages with functionality only removed
├── tailored/   # canonical OpenWrt packages adapted/recombined by capability
├── include/
├── scripts/
├── tests/
└── docs/
```

Canonical examples:

```text
audiowrt-dlna-renderer           # owned
bluez-alsa                       # ported
librespot                        # ported
alsa-lib-trimmed                 # trimmed
bluez-trimmed                    # trimmed
dbus-trimmed                     # trimmed
busybox-udhcpd-tailored          # tailored
hostapd-wpa-supplicant-tailored  # tailored
luci-mod-status-tailored         # tailored
```

## OpenWrt-derived package contract

When a package already exists in OpenWrt and AudioWRT needs a modified binary, the selected OpenWrt release is authoritative. Source-derived trimmed and tailored packages inherit:

- the exact upstream source/version selected by the canonical OpenWrt recipe;
- the complete OpenWrt patch set for that release;
- OpenWrt build flags, hardening metadata and integration files;
- the selected SDK target/subtarget/toolchain.

AudioWRT stores only its modifications on top. It does not independently pin a newer upstream source for an OpenWrt-derived package.

Binary repackages such as `dbus-trimmed` preserve the exact official OpenWrt release payload and remove only explicitly documented files.

Packages for which OpenWrt has no canonical recipe are maintained as ports from official upstream source. Current examples are `bluez-alsa` and `librespot`; there is no OpenWrt recipe or OpenWrt patch set to inherit for them.

## AudioWRT-owned runtime

Important reusable AudioWRT components include:

- `audiowrt-core`: shared runtime conventions and deterministic RAM-only device identity;
- `audiowrt-audio`: shared audio state and runtime helpers;
- `audiowrt-usb-audio`: USB Audio Class output selection;
- `libaudiowrt-player`: playback API and RAM-derived player/codec registry;
- granular `audiowrt-player-*` packages for individual playback implementations;
- `audiowrt-player-mpd`: integration for whichever official OpenWrt package provides the `mpd` capability; it does not build or replace MPD;
- `audiowrt-dlna-renderer`: native DLNA/UPnP renderer and discovery service;
- `audiowrt-bluetooth`: AudioWRT Bluetooth output integration;
- `audiowrt-wifi-client` and `audiowrt-network-client`: reusable client networking helpers;
- `audiowrt-provisioning`: AudioWRT first-boot/setup runtime.

The old `audiowrt-minimal-upmpdcli` package has been removed. The native `audiowrt-dlna-renderer` no longer requires upmpdcli or MPD to provide DLNA rendering.

## Players

Playback support is intentionally granular. Each `audiowrt-player-*` package can be selected independently.

Installed player manifests live under `/usr/share/audiowrt/players`. `libaudiowrt-player` rebuilds the derived player and codec catalogs in `/tmp/audiowrt/registry`; operational playback discovery does not rewrite flash.

Consumer modules such as the DLNA renderer choose a preferred/default player in their own configuration. Installing or removing a player does not silently change a module default.

## Theme and distribution branding

`luci-theme-audiowrt` is reusable on a normal OpenWrt installation. Installing the theme alone keeps OpenWrt identity and does not install AudioWRT logo/favicon assets.

`audiowrt-distro-branding` is the optional AudioWRT-distribution identity layer. It depends on `luci-theme-audiowrt` and provides the AudioWRT logo, favicon and system banner. AudioWRT firmware profiles select this package explicitly.

## Bluetooth stack

The constrained Bluetooth stack is composed from:

- `kmod-bluetooth-tailored` — recombines the exact-release OpenWrt Bluetooth core and USB HCI modules needed by AudioWRT from the official `kmod-bluetooth`, `kmod-btmtk` and `kmod-btusb` packages;
- `bluez-trimmed` — selected-release BlueZ with unused features removed;
- `sbc-trimmed` — selected-release SBC runtime library only;
- `bluez-alsa` — upstream BlueALSA port packaged for OpenWrt;
- `audiowrt-bluetooth` — AudioWRT integration/service layer.

The official OpenWrt `bluez-libs` package remains unchanged.

## Constrained base replacements

The constrained AudioWRT profiles may select tailored/trimmed providers while reusable packages depend on normal capabilities:

- `busybox-udhcpd-tailored` provides `busybox` and `udhcpd`;
- `hostapd-wpa-supplicant-tailored` provides `hostapd` and `wpa-supplicant` through one multicall binary;
- `luci-mod-status-tailored` provides `luci-mod-status` with the constrained status-page implementation;
- `alsa-lib-trimmed` provides `alsa-lib`;
- `dbus-trimmed` provides `dbus`;
- `dropbear-trimmed` provides `dropbear`;
- `umdns-trimmed` provides `umdns`.

This keeps the reusable package dependency contract generic while the firmware profile decides which provider is installed.

## Use as an OpenWrt feed

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git
```

Then:

```sh
./scripts/feeds update audiowrt
./scripts/feeds install -a -p audiowrt
```

Installing this feed or one of its reusable packages does **not** turn an OpenWrt router into the AudioWRT distribution. Distribution policy remains in the `audiowrt` firmware profiles.

## Persistence policy

Runtime discovery, boot, hotplug and playback state are kept in RAM wherever possible. Persistent configuration changes are reserved for explicit user save/configuration actions.

Device identity is deterministic from a permanent onboard MAC and is regenerated into `/tmp/audiowrt/uuid` at boot. Wi-Fi setup tests are staged in RAM and are persisted only by an explicit Save action.

## Architecture

File-only packages are marked `PKGARCH:=all` where possible. Native packages are built with the selected OpenWrt SDK and are target-architecture specific. Release compatibility comes from the exact selected OpenWrt release context rather than from hard-coding one global source version in this feed.

## GitHub Actions

Package validation runs on pull requests. Package builds are available through the manual package-build workflow and use the `demonccc/audiowrt` build engine.

## License

AudioWRT-owned package code is GPL-2.0-only unless stated otherwise. LuCI components use Apache-2.0. Third-party sources retain their upstream licenses.
