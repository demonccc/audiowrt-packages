# AudioWRT package taxonomy

This repository is one OpenWrt feed organized into four package families. The family is determined by ownership and provenance, not by whether AudioWRT happens to consume the package.

## Repository layout

```text
audiowrt-packages/
├── audiowrt/   # AudioWRT-owned code, integrations and UI
├── ported/     # upstream software without a canonical OpenWrt package recipe
├── trimmed/    # canonical OpenWrt packages with functionality only removed
├── tailored/   # canonical OpenWrt packages adapted or recombined for a capability set
├── include/
├── scripts/
├── tests/
└── docs/
```

The repository remains a single feed:

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git
```

The directories are organizational categories inside that feed; they are not separate feeds.

## 1. AudioWRT-owned

AudioWRT-owned packages contain code, integration, configuration, UI or distribution behavior maintained as AudioWRT functionality.

Naming:

- `audiowrt-*` for services, helpers, integrations and distribution packages;
- `libaudiowrt-*` for AudioWRT shared libraries;
- `audiowrt-player-*` for granular playback integrations;
- `luci-app-audiowrt-*` for AudioWRT LuCI applications;
- `luci-theme-audiowrt` for the reusable AudioWRT-maintained LuCI theme.

Examples:

```text
audiowrt-core
audiowrt-dlna-renderer
audiowrt-player-flac
audiowrt-player-mpd
libaudiowrt-player
luci-theme-audiowrt
```

### Distribution branding

`luci-theme-audiowrt` is reusable on a normal OpenWrt installation and does not impose AudioWRT distribution identity.

`audiowrt-distro-branding` is the optional distribution-only identity layer. It depends on `luci-theme-audiowrt` and installs the AudioWRT logo, favicon and system banner. AudioWRT firmware profiles select this package; an OpenWrt user may install the theme without installing the branding package.

### Device identity

Deterministic device identity is part of `audiowrt-core`; it is not a separate package. The core service writes `/tmp/audiowrt/uuid` from a permanent onboard MAC and never persists generated identity state.

## 2. Ported

A ported package is official upstream software for which the supported OpenWrt release has no canonical package recipe. AudioWRT maintains the OpenWrt packaging recipe directly from the official upstream source.

Naming: keep the normal upstream package name. Do not add an `audiowrt-`, `-ported`, `-trimmed` or `-tailored` suffix merely because AudioWRT maintains the OpenWrt recipe.

Current examples:

```text
bluez-alsa
librespot
```

Provenance:

```text
official upstream source
        +
AudioWRT-maintained OpenWrt package recipe
        +
AudioWRT-maintained compatibility patches/configuration, if required
        ↓
final OpenWrt package
```

There is no OpenWrt recipe or OpenWrt patch set to inherit in this category.

## 3. Trimmed

A trimmed package derives from the canonical package recipe of the selected OpenWrt release and only removes functionality or payload that the constrained runtime does not need.

Naming:

```text
<canonical-package>-trimmed
```

Current packages:

```text
alsa-lib-trimmed
bluez-trimmed
dbus-trimmed
dropbear-trimmed
glib2-trimmed
sbc-trimmed
umdns-trimmed
```

`glib2-trimmed` binary-repackages the official selected-release `glib2` APK. It retains the GLib, GObject, GModule and GIO shared libraries used by AudioWRT and omits the unused GIRepository and legacy GThread shared libraries. The staging script fails if a future official package introduces an unclassified GLib runtime library, so release upgrades require an explicit review rather than silently dropping new payload.

Source-derived trimmed packages inherit:

- the upstream source/version selected by the canonical OpenWrt recipe;
- the complete OpenWrt patch set for that release;
- OpenWrt build flags, hardening and integration files;
- the selected OpenWrt SDK target/subtarget/toolchain.

Binary repackages such as `dbus-trimmed` and `glib2-trimmed` retain the exact selected-release OpenWrt binary payload and remove only explicitly documented files.

## 4. Tailored

A tailored package starts from one or more canonical OpenWrt packages but changes the delivered capability set rather than merely deleting payload. It may enable capabilities, combine entry points, replace an implementation detail, or remove and add features at the same time.

Naming should expose the relevant capabilities:

```text
<capability-1>-<capability-2>-tailored
```

Current packages:

```text
busybox-udhcpd-tailored
hostapd-wpa-supplicant-tailored
luci-mod-status-tailored
kmod-bluetooth-tailored
```

The tailored package must document:

1. canonical OpenWrt component(s) used as the base;
2. capabilities retained;
3. capabilities removed;
4. capabilities enabled or added;
5. runtime artifacts provided;
6. `PROVIDES` / `CONFLICTS` compatibility contract where applicable.

Examples:

- `busybox-udhcpd-tailored` provides the BusyBox runtime plus the `udhcpd` capability while pruning unused applets.
- `hostapd-wpa-supplicant-tailored` builds one multicall binary exposing both `hostapd` and `wpa_supplicant` with the constrained AudioWRT feature set.
- `luci-mod-status-tailored` retains the useful LuCI status views, removes conntrack/firewall-only functionality and replaces the Processes implementation so it does not require BusyBox `top`.
- `kmod-bluetooth-tailored` recombines the exact-release kernel modules from OpenWrt's `kmod-bluetooth`, `kmod-btmtk` and `kmod-btusb` packages, retaining the Bluetooth core and USB HCI transports required by AudioWRT while omitting RFCOMM, BNEP and HIDP.

## OpenWrt-derived source contract

For trimmed and tailored source-derived packages, the selected OpenWrt release is authoritative:

```text
upstream source selected by OpenWrt
        ↓
canonical OpenWrt package recipe
        + OpenWrt patch set
        + OpenWrt build flags/integration
        ↓
AudioWRT modifications
        ↓
trimmed/tailored package
```

AudioWRT must not independently pin a newer upstream source for an OpenWrt-derived package. Release-specific AudioWRT compatibility changes may live under `releases/<major.minor>/`, but copied OpenWrt-owned source metadata or patches must not be stored there.

## Reusable packages vs AudioWRT distribution

Packages in this feed provide reusable capabilities. Installing the feed or an individual AudioWRT package must not implicitly turn a normal OpenWrt installation into the AudioWRT distribution.

Distribution-only choices belong in AudioWRT firmware profiles. Examples include selecting `audiowrt-distro-branding`, selecting constrained replacement providers, and choosing which players are present in a firmware image.

## Canonical examples

```text
audiowrt-dlna-renderer           # owned
bluez-alsa                       # ported
librespot                        # ported

bluez-trimmed                    # trimmed
alsa-lib-trimmed                 # trimmed
dbus-trimmed                     # trimmed
glib2-trimmed                    # trimmed

busybox-udhcpd-tailored          # tailored
hostapd-wpa-supplicant-tailored  # tailored
luci-mod-status-tailored         # tailored
```
