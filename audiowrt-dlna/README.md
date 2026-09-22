# AudioWRT native renderer and discovery service

`audiowrt-renderer` is the native AudioWRT network renderer. One daemon owns:

- SSDP discovery and DLNA/UPnP MediaRenderer control;
- minimal authoritative mDNS/DNS-SD for the AudioWRT hostname and LuCI HTTP service;
- the UCI codec/player registry;
- player selection and fallback;
- playback lifecycle and runtime status.

It intentionally does not depend on MPD, upmpdcli or a separate umdns daemon.

## Codec and player registry

The canonical registry lives in `/etc/config/audiowrt`. The renderer does not
hard-code FLAC, MP3, AAC, WAV, Vorbis or any other codec.

A codec declares how incoming media is recognized and which compatible player is
preferred:

```uci
config codec 'flac'
        list mime 'audio/flac'
        list mime 'audio/x-flac'
        list extension 'flac'
        option default_player 'native_flac'
```

A player declares its executable and the codecs that it supports:

```uci
config player 'native_flac'
        option name 'AudioWRT FLAC Player'
        option executable '/usr/bin/audiowrt-player-flac'
        list codec 'flac'
```

One player can support many codecs by adding more `list codec` entries. This is
the intended integration model for wrappers around VLC, MPD or another playback
engine.

Player packages register themselves idempotently with
`/usr/libexec/audiowrt-player-registry`. Registration:

- creates a missing codec but never replaces an existing codec section;
- adds only missing MIME types and extensions;
- creates a missing player but preserves an existing player configuration;
- attaches the codec to the player if needed;
- sets `default_player` only when the codec has no default yet;
- hot-reloads the running renderer after committing UCI.

Other available players for the same codec are automatic fallbacks. The configured
default is tried first; remaining compatible players are tried in UCI section order.

## Player execution contract

Every player uses the same contract:

```text
/path/to/player <URL>
```

The URL is the only command-line argument. The process must remain in the foreground
for the lifetime of playback and exit zero when playback finishes normally.

The renderer also exports:

```text
AUDIOWRT_URI
AUDIOWRT_CODEC
AUDIOWRT_MIME
AUDIOWRT_ALSA_DEVICE
AUDIOWRT_VOLUME_FILE
```

The renderer creates a process group for the player. Pause and resume use
`SIGSTOP`/`SIGCONT`; stop uses `SIGTERM` followed by `SIGKILL` if necessary.
A wrapper is responsible for adapting VLC, MPD or another engine to this contract.

Native AudioWRT players use `libuclient` directly for HTTP/HTTPS and write PCM
directly to ALSA; they must not exec wget, uclient-fetch or curl.

## Hot reload

A `SIGHUP` reloads only the codec/player registry. It does not replace the renderer
process, subscribers, UUID or active player process. After a successful reload the
renderer emits a ConnectionManager event so controllers can refresh
`SinkProtocolInfo`.

## mDNS scope

The integrated mDNS implementation is deliberately small. It answers the local
AudioWRT host A record and advertises the LuCI `_http._tcp` service. It is not a
replacement API for OpenWrt `umdns`: it does not implement browsing, reflection,
ubus integration or a generic service database.
