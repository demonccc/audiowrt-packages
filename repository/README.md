# Published AudioWRT package repository

AudioWRT package source lives in this repository. Published APKs use a separate logical repository model:

- GitHub Releases store immutable APK assets produced by incremental builds.
- Each incremental Release also stores `repository-update.json` describing exactly which package entries it updates.
- GitHub Pages rebuilds the current repository view from the complete immutable update history.
- No `gh-pages` branch is required.

## Channels

- `stable` is produced from `main`.
- `testing` is produced from `testing`.

Feature/fix branches do not publish permanent package repository state. Their package builds remain temporary CI artifacts until merged into `testing`.

## Repository identity

Pages publishes one logical repository per:

```text
channel + OpenWrt version + target + subtarget
```

The metadata also records the OpenWrt package architecture. A package entry contains its version, immutable Release URL, SHA256, source commit and source directory.

## Incremental builds

On a push to `main` or `testing`, `scripts/detect-changed-packages.py` maps changed package directories to package names and propagates only explicit rebuild relationships from `repository/rebuild-dependents.json`.

Runtime dependencies do not automatically cause downstream rebuilds. Rebuild propagation is reserved for packages that compile/link against an AudioWRT-owned provider and must be declared explicitly.

A shared build-infrastructure change falls back to rebuilding all packages.

## Bootstrap

The first repository publication for an OpenWrt build context must be run with `package=all`. Subsequent publications are incremental.
