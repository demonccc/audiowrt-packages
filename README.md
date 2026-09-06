# AudioWRT Packages

Reusable OpenWrt packages and LuCI applications that add music and audio capabilities **without changing OpenWrt's router, network, DHCP, firewall or first-boot behavior**.

This repository is an OpenWrt package feed. Distribution-only behavior belongs in [`demonccc/audiowrt`](https://github.com/demonccc/audiowrt).

## Responsibility boundary

`audiowrt-packages` is safe to use on an existing OpenWrt installation. It owns only audio functionality:

- common audio state and naming;
- USB DAC output management;
- music-service installation and configuration;
- Spotify Connect;
- AirPlay;
- MPD/local music;
- Bluetooth A2DP output;
- the reusable AudioWRT LuCI audio UI.

It does **not** change LAN addressing, DHCP serving, Wi-Fi AP/STA topology, firewall behavior, provisioning or storage layout.

AudioWRT distribution packages such as first-boot provisioning, client-only network defaults and guided USB extroot management live in the `audiowrt` repository instead.

## Packages

### `audiowrt-audio`

Common reusable audio state and helper CLI. The effective audio name defaults to the existing OpenWrt hostname unless explicitly overridden.

### `audiowrt-usb-audio`

Detects the first USB Audio Class playback device, creates the ALSA `default` output and reacts to USB hotplug. It uses `alsa-lib` rather than the full `alsa-utils` package.

### `audiowrt-extensions`

Runtime service manager using OpenWrt 25.12's `apk` package manager. The initial extension catalog contains:

- `mpd` -> `audiowrt-mpd`
- `airplay` -> `audiowrt-airplay`
- `spotify` -> `audiowrt-spotify`
- `bluetooth` -> `audiowrt-bluetooth`

Example:

```sh
audiowrt-extensions list
audiowrt-extensions install spotify
audiowrt-extensions install bluetooth
```

The manager uses the existing OpenWrt writable overlay. It never formats or reconfigures storage.

### `audiowrt-mpd`

Installs `mpd-mini` and configures local/HTTP playback through ALSA `default`. MPD database, state and playlists stay under `/tmp`; local music is expected at `/mnt/music`.

### `audiowrt-airplay`

Installs `shairport-sync-mini`, uses the current AudioWRT audio name and sends playback to ALSA `default`.

### `librespot` + `audiowrt-spotify`

The feed packages librespot 0.8.0 for OpenWrt using the official OpenWrt Rust toolchain, the ALSA backend, rustls and pure-Rust mDNS. `audiowrt-spotify` configures it as a Spotify Connect speaker using ALSA `default` and disables the audio cache to reduce writes.

librespot requires Spotify Premium.

### `bluez-alsa` + `audiowrt-bluetooth`

The feed packages the lightweight BlueALSA bridge and integrates it with OpenWrt's BlueZ packages. `audiowrt-bluetooth` supports discovery, pairing, connection and selecting an A2DP speaker/headset as ALSA `default`.

The BlueALSA package carries the known big-endian fixes used by the OpenWrt community packaging, which matters for MIPS targets such as ath79.

CLI examples:

```sh
audiowrt-bluetooth scan
audiowrt-bluetooth pair AA:BB:CC:DD:EE:FF
audiowrt-bluetooth select AA:BB:CC:DD:EE:FF
audiowrt-bluetooth usb
```

### `luci-app-audiowrt`

Reusable audio-only LuCI interface:

```text
AudioWRT
├── Overview
├── Output
└── Extensions
```

The Output page can select USB audio and, when the Bluetooth extension is installed, scan/pair/select Bluetooth speakers. The Extensions page installs/removes music services with `apk`.

When this app is used inside the full AudioWRT distribution, `luci-app-audiowrt-core` from the distribution repository adds the network/storage/system pages under the same `AudioWRT` menu.

## Use as an OpenWrt feed

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git
```

Development branch example:

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git;feat/mvp-runtime
```

Then:

```sh
./scripts/feeds update audiowrt
./scripts/feeds install -a -p audiowrt
```

## GitHub Actions policy

GitHub Actions are manual-only (`workflow_dispatch`). Pushes and pull requests do not consume hosted-runner time automatically.

## Compatibility

Development targets OpenWrt 25.12 first. Board drivers and device topology remain OpenWrt responsibilities.

## License

AudioWRT-owned package code is GPL-2.0-only unless stated otherwise. LuCI components use Apache-2.0. Third-party sources such as librespot and BlueALSA retain their upstream licenses.
