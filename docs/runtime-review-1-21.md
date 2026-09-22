# Runtime review: items 1–21

| Item | Applied change |
| --- | --- |
| 1 | S11 generates the deterministic shared UUID in `/tmp/audiowrt/uuid`. No hostname initialization or identity flag is saved. |
| 2 | mDNS reacts to runtime addresses; network events do not commit configuration or start a stopped renderer. |
| 3 | The provisioning AP uses a direct hostapd configuration and `iw`/`ip`, outside UCI/netifd configuration. |
| 4 | AP configuration, leases, process IDs and diagnostics live under `/tmp/audiowrt/setup`. |
| 5 | Saving Wi-Fi applies only the tested station fields and its radio enable flag; no AP settings are persisted. |
| 6 | Connect tests in RAM. Save is separate. Provisioning checks actual Ethernet or managed station link plus IP, including static addresses. A single-radio test restores the AP for Save. |
| 7 | Removed `audiowrt-storage`. Use official OpenWrt storage/extroot tools. |
| 8 | Removed the storage LuCI module and builder targets. No automatic internal-flash mirroring remains. |
| 9 | Wi-Fi, Bluetooth, renderer preferences and extension UCI saves use isolated copies and compare before writing. Unrelated staged deltas remain uncommitted. The renderer UI does not use a global LuCI apply. |
| 10 | The default renderer/Spotify name follows the hostname; AirPlay uses its hostname token. Explicit names remain user preferences. |
| 11 | USB and Bluetooth share the RAM audio-state writer and ALSA route helper. |
| 12 | One engine restart helper detects actual output changes and touches only running, enabled engines. |
| 13 | No empty ALSA configuration is created at boot. The optional additional route is generated in RAM when needed. |
| 14 | Bluetooth device/status queries do not start services. |
| 15 | Player manifests are the single capability source. Boot/install/removal rebuild the derived catalogs in RAM. |
| 16 | Removed AudioWRT `uci-defaults` migrations and persistent first-run flags. Package data and startup symlinks are installed at build time; the builder bakes optional extension defaults from the same templates used by explicit install/configure actions. |
| 17 | A single procd provisioning supervisor owns final handoff and cleanup. Status CGI is read-only. |
| 18 | Removed obsolete provisioning wrappers, UUID generation and registry migration paths; setup constants remain in one runtime helper. |
| 19 | hostapd and udhcpd belong only to provisioning. No standalone udhcpd service or `killall`; cleanup checks owned PIDs. |
| 20 | Own generated files use `/tmp`. The image builder rejects persistent `/var`; service supervision uses OpenWrt procd conventions. |
| 21 | Fast shell contracts and behavioral tests with real UCI and simulated hardware. Full feed metadata validation is manual, not part of every push. |

## Validation and limits

Behavior tests cover unrelated staged changes, unchanged saves, concurrent
persistent edits, connection without saving, invalid-IP rollback, Ethernet/STA
link plus IP, AP exclusion, failed hostapd cleanup, renderer validation, disabled
audio engines, idempotent output selection and rebuilding/removing shared codecs.

No router was flashed or modified during these checks. They do not prove radio
driver behavior: ACS, association, DHCP delivery, browser reconnection after a
single-radio test and final handoff must still be exercised on the target build.
Configuration saves are atomic per file; multiple files are not one atomic
transaction. The broader custom-upstream runtime-write audit (item 22) is outside
this requested 1–21 change set.
