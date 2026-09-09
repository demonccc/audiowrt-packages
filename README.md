# AudioWRT Packages

Reusable OpenWrt packages and LuCI applications used by AudioWRT.

This repository is an OpenWrt package feed. Distribution-only appliance policy belongs in [`demonccc/audiowrt`](https://github.com/demonccc/audiowrt).

## Responsibility boundary

Packages in this repository are safe to install on an existing OpenWrt system. Installing them must not silently replace the device's existing router, DHCP, firewall, storage or first-boot policy.

Most packages are audio-only. Reusable system helpers such as `audiowrt-wifi-client` are **opt-in**: they install disabled and change configuration only after an explicit user or distribution action.

The AudioWRT firmware repository is responsible for deciding which reusable components are enabled during first boot.

## Packages

### `audiowrt-audio`

Common reusable audio state and helper CLI. The OpenWrt system hostname (`system.@system[0].hostname`) is the canonical AudioWRT device/audio name; it is not duplicated in AudioWRT UCI state.

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

### `audiowrt-wifi-client`

Reusable Wi-Fi STA/setup-AP helper. It can scan every OpenWrt `wifi-device`, configure an `audiowrt_client` STA on the selected radio, provide an explicit setup/recovery AP and keep mDNS enabled on the AudioWRT client/setup interfaces.

The package is disabled by default. Installing it on normal OpenWrt does not modify `/etc/config/network`, `/etc/config/wireless`, DHCP or mDNS until the user explicitly invokes it.

Examples:

```sh
audiowrt-wifi-client scan
audiowrt-wifi-client status
audiowrt-wifi-client connect radio1 'My Wi-Fi' sae-mixed 'password'
```

`luci-app-audiowrt-wifi-client` exposes the same opt-in capability as **Network -> Wi-Fi Client**.

### `audiowrt-mpd`

Installs `mpd-mini` and configures local/HTTP playback through ALSA `default`. MPD database, state and playlists stay under `/tmp`; local music is expected at `/mnt/music`.

### `audiowrt-airplay`

Installs `shairport-sync-mini`, uses the current OpenWrt hostname as the AudioWRT audio name and sends playback to ALSA `default`.

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

Reusable audio LuCI interface:

```text
AudioWRT
├── Output
└── Extensions
```

When OpenWrt's `luci-mod-status` is installed, the package also adds an **AudioWRT** section to the native **Status -> Overview** page instead of maintaining a duplicate AudioWRT overview page.

## Architecture

File-only AudioWRT packages use `PKGARCH:=all` and can be reused across CPU architectures for the same compatible OpenWrt release. Packages that compile native software, notably `librespot` and `bluez-alsa`, remain architecture-specific.

`PKGARCH:=all` does not mean release-independent: development currently targets OpenWrt 25.12 and its `apk` package manager and package ABI.

## Use as an OpenWrt feed

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git
```

Development branch example:

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git;feat/reusable-wifi-client
```

Then:

```sh
./scripts/feeds update audiowrt
./scripts/feeds install -a -p audiowrt
```

Installing feed metadata does not activate `audiowrt-wifi-client`; network changes remain opt-in.

## GitHub Actions policy

GitHub Actions are manual-only (`workflow_dispatch`). Pushes and pull requests do not consume hosted-runner time automatically.

## Compatibility

Development targets OpenWrt 25.12 first. Board drivers and device topology remain OpenWrt responsibilities.

## License

AudioWRT-owned package code is GPL-2.0-only unless stated otherwise. LuCI components use Apache-2.0. Third-party sources such as librespot and BlueALSA retain their upstream licenses.
