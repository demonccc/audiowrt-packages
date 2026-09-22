# AudioWRT BlueALSA baseline

AudioWRT uses Bluetooth as an **audio output**: the router sends audio to a Bluetooth speaker or headset using the A2DP Source role.

For the 8 MB reference baseline, the BlueALSA package intentionally keeps only:

- the `bluealsa` daemon;
- ALSA BlueALSA PCM/control plugins;
- SBC support required for baseline A2DP interoperability.

The build intentionally disables `bluealsa-aplay`, CLI/RFCOMM/HCITOP tools, tests, systemd integration and optional codecs/profiles. `bluealsa-aplay` is useful for the opposite direction (playing audio received from a Bluetooth source through a local ALSA device) and is not needed for AudioWRT's router-to-speaker path.

BlueALSA 4.1.1 also requires the local GCC 14 + musl compatibility patch in `patches/005-fix-gcc14-musl-basename.patch`. GCC 14 rejects the legacy implicit `basename()` declaration; the patch uses the POSIX `<libgen.h>` declaration.
