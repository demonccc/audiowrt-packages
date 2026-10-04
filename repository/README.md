# Published AudioWRT package repository

AudioWRT package sources live in this repository. Package compilation reuses the canonical package-mode builder from `demonccc/audiowrt`, while this repository owns planning, testing publication, production promotion, repository metadata and Pages.

## Release flow

The package lifecycle deliberately separates build, testing publication and production promotion:

1. Merges to `testing` run **Build AudioWRT Packages**.
2. Build jobs run independently by logical scope/context (`all`, architecture and kernel target) and upload successful APKs as GitHub Actions artifacts. They do not create Releases.
3. **Publish AudioWRT Packages to Testing** is a manual workflow. Given a build run ID, it publishes the exact successful APK artifacts from that run to testing Releases.
4. Tested package releases are added to `repository/production-packages.yaml`.
5. When that manifest change reaches `main`, **Promote Production Packages** copies the exact testing APK bytes to stable Releases after validating SHA256. Nothing is rebuilt on `main`.
6. **Publish Package Repository Pages** rebuilds the current testing/stable repository view from immutable Release metadata.

This keeps source acceptance and binary promotion separate: a package can exist in testing for as long as necessary without becoming production, and stable always contains the same artifact that was tested.

## Production package manifest

`repository/production-packages.yaml` is the production whitelist. Its root keys are package scope categories:

```yaml
all:
  package-name:
    - release: "1.2.3-r1"
      openwrt_versions:
        - "25.12.5"
        - "25.12.6"

architectures:
  mips_24kc:
    package-name:
      - release: "1.2.3-r1"
        openwrt_versions:
          - "25.12.5"

targets:
  ath79/generic:
    package-name:
      - release: "6.6.110-r1"
        openwrt_versions:
          - "25.12.5"
```

A package may have multiple approved releases, and one package release may be approved for multiple OpenWrt versions. The manifest intentionally contains only human-maintained approval data. Release tags, source commits and SHA256 values are resolved and verified automatically from the testing repository.

## Channels

- `testing` contains manually published build artifacts selected from completed testing build runs.
- `stable` contains only package releases explicitly listed in `repository/production-packages.yaml` after that manifest reaches `main`.

Feature/fix branches validate tooling but never publish package repository state.

## Architecture-first build matrix

`repository/build-matrix.toml` defines the build contexts that participate automatically. Configuration is grouped by package architecture first, then by OpenWrt version.

For each architecture/version:

- `sdk_target` is the canonical OpenWrt target/subtarget used to compile architecture-scoped userspace packages once.
- `kernel_targets` lists every target/subtarget that needs its own kernel-scoped package build.

`PKGARCH:=all` packages are planned as their own logical `all` build job. The builder may use a concrete SDK internally, but repository state and publication remain scope `all` rather than being mixed into that SDK architecture.

## Package scopes

The planner derives scope from each package Makefile:

- `all`: `PKGARCH:=all`; built once per enabled OpenWrt version.
- `arch`: normal userspace package; built once per enabled package architecture/version.
- `kernel`: `KernelPackage/*`; built once per enabled target/subtarget/version.

## Incremental builds

Merges to `testing` run `scripts/plan-package-builds.py` against the published testing state. The planner resolves changed package source directories plus explicit compile/link dependents declared in `repository/rebuild-dependents.json`, then emits a dynamic GitHub Actions matrix.

Architecture jobs use `fail-fast: false`, so a failure in one architecture does not cancel sibling architectures. Successful package outputs remain available as workflow artifacts even when another package in that job fails.

## Published repository layout

Pages publishes scope-specific current views:

```text
<channel>/<openwrt-version>/all/repository.json
<channel>/<openwrt-version>/packages/<arch>/repository.json
<channel>/<openwrt-version>/targets/<target>/<subtarget>/repository.json
```

The root `index.json` catalogs every current repository view, and `index.html` provides a browsable summary. A firmware profile can compose the `all`, package-architecture and target repositories appropriate for its OpenWrt build context without causing package recompilation.
