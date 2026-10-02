# Published AudioWRT package repository

AudioWRT package source and its build engine live in this repository. The package pipeline is intentionally independent from `demonccc/audiowrt`: it uses official OpenWrt SDKs and this repository itself as an OpenWrt feed.

- GitHub Releases store immutable APK assets produced by incremental builds.
- Each successful build context stores `repository-update.json` describing exactly which package entries it updates.
- GitHub Pages rebuilds the current repository view from the complete immutable update history.
- Failed build contexts never cancel sibling architectures and never replace the last known-good package state.

## Channels

- `stable` is produced from `main`.
- `testing` is produced from `testing`.

Feature/fix branches validate tooling but do not publish permanent package repository state.

## Architecture-first build matrix

`repository/build-matrix.toml` is the only list of build contexts that participate automatically. Configuration is grouped by package architecture first, then by OpenWrt version.

For each architecture/version:

- `sdk_target` is the canonical OpenWrt target/subtarget used to compile architecture-scoped userspace packages once.
- `kernel_targets` lists every target/subtarget that needs its own kernel-scoped package build.

An architecture/version absent from this file is not built automatically. Adding it is an explicit support decision and bootstraps that new context through the normal merge-triggered pipeline.

## Package scopes

The planner derives scope from each package Makefile:

- `all`: `PKGARCH:=all`; built once per enabled OpenWrt version.
- `arch`: normal userspace package; built once per enabled package architecture/version.
- `kernel`: `KernelPackage/*`; built once per enabled target/subtarget/version.

## Incremental builds

Every merge to `testing` or `main` runs `scripts/plan-package-builds.py` against the merge delta. The planner resolves only changed package source directories plus explicit compile/link dependents declared in `repository/rebuild-dependents.json`, then emits a dynamic GitHub Actions matrix.

Each matrix entry is one independent package source + OpenWrt context. GitHub Actions uses `fail-fast: false`, so an architecture-specific failure does not cancel other architectures. Successful contexts publish immediately; failed contexts keep their previous repository state.

## Context-scoped patches

Common AudioWRT patches remain directly under `patches/` and apply to every context. Architecture- or target-specific patches use:

```text
patches/arch/<arch>/*.patch
patches/target/<target>/<subtarget>/*.patch
```

The same structure is supported below a release family:

```text
releases/25.12/patches/arch/<arch>/*.patch
releases/25.12/patches/target/<target>/<subtarget>/*.patch
```

Changing an architecture-specific patch rebuilds only that architecture. Changing a target-specific patch rebuilds only that target/subtarget. Common Makefile/source/patch changes rebuild all enabled contexts applicable to that package scope.

## Published repository layout

Pages publishes scope-specific current views:

```text
<channel>/<openwrt-version>/all/repository.json
<channel>/<openwrt-version>/packages/<arch>/repository.json
<channel>/<openwrt-version>/targets/<target>/<subtarget>/repository.json
```

A firmware profile can therefore compose the `all`, package-architecture and target repositories appropriate for its OpenWrt build context without causing package recompilation.
