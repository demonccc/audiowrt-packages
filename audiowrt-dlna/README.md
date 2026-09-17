# AudioWRT native DLNA player registry

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
