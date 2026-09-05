# AudioWRT Packages

Reusable OpenWrt packages and LuCI applications that provide AudioWRT runtime capabilities. The repository is consumed as an OpenWrt package feed and the packages remain usable on standard OpenWrt installations.

## Package model

AudioWRT separates the small always-present core from optional audio engines.

### Core packages

- `audiowrt-core`: device identity, Ethernet DHCP-client defaults, first-boot Wi-Fi provisioning, recovery and lightweight setup UI.
- `audiowrt-usb-audio`: USB Audio Class support and automatic ALSA output selection. It intentionally depends on `alsa-lib`, not the full `alsa-utils` package.
- `audiowrt-storage`: optional external extension storage backed by OpenWrt extroot. The internal firmware remains the boot fallback when the external device is removed.
- `audiowrt-extensions`: runtime extension catalog and installer using OpenWrt's `apk` package manager.
- `luci-app-audiowrt`: focused LuCI pages for AudioWRT status, storage and extensions.

### Optional audio engines

- `audiowrt-mpd`: preinstalls `mpd-mini` and applies the AudioWRT MPD integration.
- `audiowrt-airplay`: preinstalls `shairport-sync-mini` and applies the AudioWRT AirPlay integration.

The same MPD and AirPlay integrations are available at runtime through `audiowrt-extensions`, so constrained devices do not need to include these engines in the firmware image.

## External extension storage

Small routers may not have enough internal flash for every audio engine. AudioWRT can prepare an unused USB partition as ext4 extension storage. After reboot, OpenWrt uses it as the writable overlay, so `apk` installs additional packages there transparently.

The design keeps the internal AudioWRT core bootable. If external storage is absent, OpenWrt falls back to the internal overlay. AudioWRT also attempts to synchronize critical network and AudioWRT configuration back to the internal overlay while external storage is active.

Normal audio runtime state is kept in RAM where practical. For example, MPD database, playlists and state live under `/tmp`; local music is expected under `/mnt/music`.

`audiowrt-storage enable` is intentionally destructive and always requires an explicit `--yes` confirmation.

## First-boot flow

1. The normal Ethernet interface becomes a DHCP client.
2. AudioWRT creates a temporary isolated `AudioWRT-XXXX` setup AP when Wi-Fi is available.
3. The setup page is served at `http://192.168.77.1/`.
4. The user selects the home Wi-Fi network and AudioWRT switches to STA mode.
5. A failed Wi-Fi attempt restores the setup AP.
6. After successful provisioning the setup AP does not automatically reopen. Holding the WPS button for at least five seconds explicitly re-enters provisioning mode.

## USB audio

`audiowrt-usb-audio` detects the first USB Audio playback device from the kernel ALSA metadata, writes `/etc/asound.conf`, exposes an ALSA `default` device through `dmix`, reacts to USB hotplug and restarts installed audio services after the output changes.

## Runtime extensions

The initial catalog contains only extensions that are functional and backed by packages available from OpenWrt:

```sh
audiowrt-extensions list
audiowrt-extensions install mpd
audiowrt-extensions install airplay
```

Spotify Connect is intentionally not advertised yet because AudioWRT does not currently provide a maintained `librespot` binary package feed.

## Use as an OpenWrt feed

Add the repository to `feeds.conf`:

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git
```

For a development branch:

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git;feat/mvp-runtime
```

Then run:

```sh
./scripts/feeds update audiowrt
./scripts/feeds install -a -p audiowrt
```

## CI policy

GitHub Actions in this repository are manual-only. They never run on push or pull request events. Run `Validate AudioWRT packages` with `workflow_dispatch` only when package metadata validation is needed.

## Compatibility

Development targets the OpenWrt 25.12 stable line first. Board drivers, firmware, USB host controllers and device topology remain OpenWrt responsibilities.

## License

The repository is distributed under GPL-2.0-only unless a package or file states a different license. LuCI components use Apache-2.0 where appropriate.
