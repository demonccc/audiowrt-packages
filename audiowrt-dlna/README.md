# AudioWRT native renderer and discovery service

`audiowrt-renderer` is the native AudioWRT network renderer. One daemon owns:

- SSDP discovery and DLNA/UPnP MediaRenderer control;
- minimal authoritative mDNS/DNS-SD for the AudioWRT hostname and LuCI HTTP service;
- codec/player autodetection;
- custom player overrides;
- playback lifecycle and runtime status.

It intentionally does not depend on MPD, upmpdcli or a separate umdns daemon.

## Player registry

Official codec packages register themselves by installing one descriptor under:

`/usr/share/audiowrt/dlna/players/<codec>.conf`

Descriptor keys:

```text
id=flac
name=AudioWRT FLAC Player
command=/usr/bin/audiowrt-player-flac
mime=audio/flac audio/x-flac
extensions=flac
package=audiowrt-player-flac
```

The installed descriptor is the autodetected default. A user-defined `config player`
section in `/etc/config/audiowrt-dlna` with the same `codec` overrides the effective
command, MIME types and extensions without deleting or modifying the installed
descriptor. Removing the override immediately restores the package default.

Official players receive the source URI as their first argument. They are responsible
for transport, decoding and audio output. Native AudioWRT players use `libuclient`
directly for HTTP/HTTPS and write PCM directly to ALSA; they must not exec wget,
uclient-fetch or curl.

## mDNS scope

The integrated mDNS implementation is deliberately small. It answers the local
AudioWRT host A record and advertises the LuCI `_http._tcp` service. It is not a
replacement API for OpenWrt `umdns`: it does not implement browsing, reflection,
ubus integration or a generic service database.
