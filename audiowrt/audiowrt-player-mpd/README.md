# AudioWRT MPD player adapter

`audiowrt-player-mpd` exposes the existing OpenWrt MPD instance as an AudioWRT playback backend.

It intentionally does **not** replace `/etc/mpd.conf`, change MPD audio outputs, or create a second MPD instance.

## Listener selection

At installation time the adapter inspects `/etc/mpd.conf`:

- no `bind_to_address`: use `127.0.0.1` and MPD's configured/default port because MPD defaults to listening on `any`;
- existing localhost/loopback/any listener: reuse it;
- only explicit non-local listeners: append a dedicated `127.0.0.1:16600` listener without rewriting the rest of the file.

If a new listener is appended, AudioWRT requests a non-disruptive MPD reload. A full restart is not forced; LuCI reports when a restart may still be required.

The selected endpoint is stored in `/etc/config/audiowrt_mpd` and can be changed from LuCI under **AudioWRT → MPD**.

## Codec capabilities

Codec discovery happens at package installation and is persisted in `/etc/audiowrt/mpd-codecs.conf`.

The detector prefers MPD's `decoders` protocol command, which reports enabled decoder plugins, suffixes and MIME types. If the daemon is not running yet, it falls back to `mpd --version` and detects the compiled decoder plugins/suffixes without starting or restarting MPD.

If the installed MPD variant changes later, refresh manually with:

```sh
audiowrt-mpd-refresh-codecs refresh
```

The same action is available from the LuCI MPD page.
