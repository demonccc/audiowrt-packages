# AudioWRT Packages

Reusable OpenWrt packages and LuCI applications used by AudioWRT.

This repository is the single catalog of every package maintained by AudioWRT. It includes reusable capabilities and distribution packages such as first-boot provisioning. Installing a package provides capability; the [`demonccc/audiowrt`](https://github.com/demonccc/audiowrt) distribution selects packages through its `minimal`, `standard` and `full` profiles.

The constrained AudioWRT baseline also builds two release-compatible runtime
library replacements from this feed:

- `audiowrt-minimal-alsa` replaces `alsa-lib`, keeping PCM, mixer/control and only the PCM plugins used by AudioWRT
  USB Audio and BlueALSA; MIDI, Sequencer, topology, UCM and unrelated
  interfaces are omitted;
- `audiowrt-minimal-mbedtls` replaces `libmbedtls21`, keeping WPA2/WPA3 and modern HTTPS/package-verification support
  while removing unused curves and TLS-PSK modes.

Both packages retain the upstream ABI and use a higher package release than
the corresponding OpenWrt 25.12 binaries so the ImageBuilder selects the
AudioWRT implementation without changing consumers.

## Responsibility boundary

Reusable packages in this feed provide capabilities. They do not decide that an OpenWrt device should become an AudioWRT appliance.

Audio capabilities include USB DAC output management, MPD/local music, AirPlay, Spotify Connect, Bluetooth A2DP output, extension management and the reusable AudioWRT LuCI audio UI.

The reusable `audiowrt-wifi-client` capability can scan and configure Wi-Fi station mode and a temporary setup AP, but it is inert after installation until an explicit command or LuCI action enables it. The AudioWRT distribution owns the policy that activates this capability during first-boot provisioning.

Distribution behavior such as first-boot provisioning, client-only appliance defaults and guided USB extroot management is packaged here. Profile selection and firmware policy remain in the `audiowrt` repository.

## Packages

### `audiowrt-audio`

Common reusable audio state and helper CLI. The device/audio name is derived from OpenWrt's canonical `system.hostname`; AudioWRT does not keep a duplicate hostname in its own UCI config.

### `audiowrt-usb-audio`

Detects the first USB Audio Class playback device, creates the ALSA `default` output and reacts to USB hotplug. It uses the `audiowrt-minimal-alsa` replacement rather than the full upstream ALSA userspace package.

### `audiowrt-extensions`

Runtime service manager using OpenWrt 25.12's `apk` package manager. The initial extension catalog contains MPD, AirPlay, Spotify and Bluetooth.

### `audiowrt-mpd`

Installs `mpd-mini` and configures local/HTTP playback through ALSA `default`.

### `audiowrt-airplay`

Installs `shairport-sync-mini`, uses the current OpenWrt hostname as the AudioWRT audio name and sends playback to ALSA `default`.

### `librespot` + `audiowrt-spotify`

Packages librespot 0.8.0 with the official OpenWrt Rust toolchain, ALSA backend, rustls and pure-Rust mDNS. Spotify Premium is required by librespot.

### `bluez-alsa` + `audiowrt-bluetooth`

Packages the lightweight BlueALSA bridge and integrates it with OpenWrt's BlueZ packages. The BlueALSA package carries the known big-endian fixes used by the OpenWrt community packaging.

### `audiowrt-wifi-client`

Reusable Wi-Fi client backend. It can:

- enumerate and scan every OpenWrt Wi-Fi radio;
- create/update the `audiowrt_wifi` DHCP client interface;
- create/update the `audiowrt_client` STA interface on the selected radio;
- create/stop a temporary `audiowrt_setup` AP when explicitly requested;
- keep uMDNS bound to the normal LAN, AudioWRT Wi-Fi client and setup networks.

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

Installing packages from the feed does not turn an OpenWrt router into the AudioWRT distribution. For example, installing `audiowrt-wifi-client` is inert until the user explicitly configures a client connection.

## Architecture

File-only packages are marked `PKGARCH:=all` where possible. Packages that compile native software, notably `librespot` and `bluez-alsa`, remain target-architecture specific. `all` still means package architecture, not cross-release compatibility; development targets OpenWrt 25.12 first.

## GitHub Actions policy

GitHub Actions are manual-only (`workflow_dispatch`). Pushes and pull requests do not consume hosted-runner time automatically.

## License

AudioWRT-owned package code is GPL-2.0-only unless stated otherwise. LuCI components use Apache-2.0. Third-party sources retain their upstream licenses.
