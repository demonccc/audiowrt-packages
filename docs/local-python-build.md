# Container-native Python SDK package builder

`scripts/build.py` is an in-container entrypoint. It never starts Docker.
The caller (laptop or GitHub Actions) starts the canonical Docker image
and mounts the repository at `/workspace`.

List packages:

```bash
docker run --rm --user "$(id -u):$(id -g)" \
  -e HOME=/tmp -e PYTHONUNBUFFERED=1 \
  -v "$PWD:/workspace" -w /workspace \
  demonccc/openwrt-builder:latest \
  python3 scripts/build.py list
```

Build a single package with a full log saved on the host:

```bash
docker run --rm --user "$(id -u):$(id -g)" \
  -e HOME=/tmp -e PYTHONUNBUFFERED=1 \
  -v "$PWD:/workspace" -w /workspace \
  demonccc/openwrt-builder:latest \
  python3 scripts/build.py build \
    --release 25.12.5 --arch mips_24kc \
    --target ath79 --subtarget generic \
    --package bluez-trimmed --jobs 4 \
    --log-file logs/bluez-trimmed.log
```

Replace `--package bluez-trimmed` with `--package all` to select
all packages. The `--log-file` option writes both stdout and stderr to a
file under the mounted checkout while streaming the same output to the terminal.
The log persists after the container exits, even if compilation fails.
The same container command is suitable for CI.

This branch contains an experimental extracted compilation implementation:
package-specific Bluetooth, audio and Wi-Fi dependencies have not all been
validated. No GitHub Actions publishing workflow is changed.
