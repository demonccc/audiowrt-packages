# Local Python SDK build experiment

This branch adds standalone Python SDK compilation without firmware profiles or the AudioWRT repository.

```bash
python3 scripts/build.py list
python3 scripts/build.py build --release 25.12.5 --arch mips_24kc --package bluez-trimmed --target ath79 --subtarget generic --jobs 4
```

The CLI runs within `demonccc/openwrt-builder:latest` and delegates to `scripts/build-sdk.py` in this repository. The new code does not invoke the legacy `build-package-context.sh` or `build-package-batch.sh`.

This is an experimental first extraction. Package-specific Bluetooth, audio and Wi-Fi SDK staging paths have not been validated, nor has a complete package build. Do not merge to testing on the basis of CLI operation alone. GitHub Actions publishing remains untouched.

To save the complete build log while keeping console output:

```bash
python3 scripts/build.py build \
  --release 25.12.5 --arch mips_24kc \
  --target ath79 --subtarget generic \
  --package bluez-trimmed --jobs 4 \
  --log-file logs/bluez-trimmed.log
```

Logs live on the host under the checkout, survive Docker removal, include stderr
and stdout, and remain available after unsuccessful builds. Use a log path
outside `output/local` and `.cache/audiowrt-packages`.
