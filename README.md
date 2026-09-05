# AudioWRT Packages

Reusable OpenWrt packages and LuCI applications that provide the audio capabilities used by AudioWRT and can also be installed on standard OpenWrt systems.

This repository is intended to be consumed as an OpenWrt package feed.

## MVP package set

### `audiowrt-core`

Provides the AudioWRT runtime and first-boot provisioning flow:

- derives a device name such as `AudioWRT-A4F2` from the device MAC address
- changes the normal OpenWrt LAN from router-side static addressing to DHCP client mode
- disables DHCP server behavior on the normal LAN
- creates a temporary isolated `AudioWRT-XXXX` Wi-Fi setup AP when a radio is available
- serves a lightweight first-boot setup page at `http://192.168.77.1/`
- configures a Wi-Fi STA connection from that setup page
- restores the setup AP automatically when a Wi-Fi connection attempt fails
- never automatically reopens the setup AP after successful provisioning
- supports explicitly re-entering provisioning mode by holding a WPS button for at least five seconds

Ethernet remains usable as a DHCP client and provides the fallback setup path on devices without Wi-Fi.

### `audiowrt-usb-audio`

Provides USB Audio Class support and runtime output management:

- depends on `kmod-usb-audio` and ALSA utilities
- detects the first USB Audio playback device
- generates `/etc/asound.conf`
- exposes a shared ALSA `default` output through `dmix`
- updates AudioWRT runtime status
- reacts to USB hotplug events
- restarts audio services after the output changes

### `audiowrt-mpd`

Provides a functional MPD configuration for local and HTTP playback through the AudioWRT ALSA output. Music is expected at `/mnt/music`, while MPD database and playlist state stay in `/tmp` to avoid unnecessary flash writes.

### `audiowrt-airplay`

Provides a functional AirPlay receiver using the minimal Shairport Sync variant and the AudioWRT ALSA output. The AirPlay receiver name follows the AudioWRT device name.

### `luci-app-audiowrt`

Provides an authenticated LuCI overview for device, network and audio status. First-boot Wi-Fi setup intentionally uses the much smaller dedicated setup page rather than requiring LuCI authentication.

## Use as an OpenWrt feed

Add this repository to `feeds.conf` or `feeds.conf.default`:

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git
```

For development branches:

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git;branch=feat/mvp-runtime
```

Then run:

```sh
./scripts/feeds update audiowrt
./scripts/feeds install -a -p audiowrt
```

## Compatibility

Development targets the OpenWrt 25.12 stable line first. AudioWRT packages avoid board-specific assumptions; board drivers, firmware and device topology remain OpenWrt responsibilities.

## License

The repository is distributed under GPL-2.0-only unless a package or file states a different license. LuCI components use Apache-2.0 where appropriate.
