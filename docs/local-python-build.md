# Local package builder experiment

This branch provides a profile-free Python entry point, executed inside the existing
`demonccc/openwrt-builder:latest` Docker image. It does **not** clone or run
`demonccc/audiowrt` and it does not build a firmware image.

From this checkout on Linux:

```bash
docker pull demonccc/openwrt-builder:latest
python3 scripts/build.py list
python3 scripts/build.py build --release 25.12.5 --arch mips_24kc --package bluez-trimmed --jobs 4
```

For every package in that architecture:

```bash
python3 scripts/build.py build --release 25.12.5 --arch mips_24kc --package all --jobs 4
```

Use `--target ath79 --subtarget generic` to restrict the SDK to one target,
otherwise the matrix also includes kernel targets where configured.

Outputs are stored in `output/local/`, and persistent downloads in
`.cache/audiowrt-packages/`.

**Current limitation:** Python owns the CLI, Docker invocation, package selection,
and target mapping. The actual package compilation still invokes the repository's
existing `build-package-batch.sh` / `build-package-context.sh`. This is a first
local-testing stage, not yet a full Python port of the known-good compilation code.
No GitHub Actions publishing workflow is changed by this branch.
