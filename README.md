# AudioWRT Packages

Reusable OpenWrt packages and LuCI applications that provide the audio capabilities used by AudioWRT and can also be installed on standard OpenWrt systems.

This repository is intended to be consumed as an OpenWrt package feed.

## Goals

- Keep AudioWRT audio functionality independent from the distribution repository.
- Reuse official OpenWrt packages whenever possible.
- Provide small, composable packages for audio transports and services.
- Provide a focused LuCI experience for AudioWRT.
- Keep the packages usable on standard OpenWrt installations.

## Initial packages

- `audiowrt-core`: AudioWRT runtime defaults and shared helpers.
- `audiowrt-usb-audio`: USB Audio Class support and ALSA utilities.
- `audiowrt-mpd`: local and network music playback through MPD.
- `audiowrt-airplay`: AirPlay receiver support through Shairport Sync.
- `luci-app-audiowrt`: focused AudioWRT web interface.

Spotify Connect and Bluetooth audio are planned as separate packages after compatibility and dependency validation.

## Use as an OpenWrt feed

Add this repository to `feeds.conf` or `feeds.conf.default`:

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git
```

Then run:

```sh
./scripts/feeds update audiowrt
./scripts/feeds install -a -p audiowrt
```

## Compatibility

Development starts with the OpenWrt 25.12 stable line.

## License

The repository is distributed under GPL-2.0-only unless a package or file states a different license. LuCI components may use Apache-2.0 where appropriate.
