#!/usr/bin/env python3
"""Standalone OpenWrt SDK package compiler (no firmware profiles).

Port of the package-only phase of the AudioWRT SDK build: the repository owns
the package graph, the official SDK supplies the cross compiler and dependencies,
and only requested package roots are compiled. No AudioWRT checkout is used.
"""
from __future__ import annotations

import argparse
import fcntl
from contextlib import contextmanager
import json
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATEGORIES = ("audiowrt", "ported", "trimmed", "tailored")

class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.links.extend(value for key, value in attrs if key == "href")

def run(*cmd, cwd=None):
    print("+", " ".join(map(str,cmd)), flush=True)
    subprocess.run([str(x) for x in cmd], cwd=cwd, check=True)

def package_sources():
    sources = {}
    for category in CATEGORIES:
        for makefile in (ROOT / category).glob("*/Makefile"):
            text = makefile.read_text()
            for name in re.findall(r"^define Package/([^\s]+)", text, re.M):
                sources[name] = makefile.parent
            for name in re.findall(r"^define KernelPackage/([^\s]+)", text, re.M):
                sources["kmod-" + name] = makefile.parent
    return sources

def download_sdk(release, target, subtarget, cache):
    url = f"https://downloads.openwrt.org/releases/{release}/targets/{target}/{subtarget}/"
    parser = Links()
    with urllib.request.urlopen(url, timeout=60) as response:
        parser.feed(response.read().decode("utf-8", "replace"))
    names = [n for n in parser.links if n.startswith(f"openwrt-sdk-{release}-") and
             n.endswith((".tar.zst", ".tar.xz")) and "Linux-x86_64" in n]
    if not names:
        raise RuntimeError(f"No official SDK found at {url}")
    expected = [n for n in names if f"-{target}-{subtarget}_" in n]
    archive = (expected or names)[0]
    destination = cache / archive
    if not destination.is_file():
        tmp = destination.with_suffix(destination.suffix + ".part")
        # Retry and resume. curl is already present in the canonical Docker image.
        run("curl", "--http1.1", "--fail", "--location", "--retry", "10",
            "--retry-all-errors", "--retry-delay", "3", "--continue-at", "-",
            "--output", tmp, url + archive)
        tmp.rename(destination)
    return destination

def sdk_root(archive, work):
    if archive.name.endswith(".tar.zst"):
        run("tar", "--zstd", "-xf", archive, "-C", work)
    else:
        with tarfile.open(archive, "r:xz") as tar:
            tar.extractall(work, filter="data")
    candidates = [d for d in work.iterdir() if d.is_dir()]
    if len(candidates) != 1:
        raise RuntimeError("SDK archive must have exactly one root directory")
    return candidates[0]

def package_map():
    result = {}
    for line in (ROOT / "config/build/package-build-targets").read_text().splitlines():
        if "|" in line and not line.lstrip().startswith("#"):
            package, target = line.split("|", 1)
            result[package] = target
    return result

def register_upstream_sdk_sources(sdk, cache, requirements):
    """Sparse-materialize exact SDK-pinned recipes without installing whole feeds."""
    import importlib.util

    module_path = ROOT / "scripts/materialize-openwrt-feed-source.py"
    spec = importlib.util.spec_from_file_location("audiowrt_materialize", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    feed_paths = {}
    for feed, source_path in requirements:
        feed_paths.setdefault(feed, set()).add(source_path)

    recipe_targets = {}
    for feed, paths in feed_paths.items():
        source, subroot = module.read_feed_source(sdk, feed)
        checkout = cache / "upstream-source" / feed
        # The persistent cache intentionally contains all *configured sparse*
        # source paths, matching AudioWRT's canonical SDK preparation.
        configured = module.read_paths(ROOT / "config/build/openwrt-source-paths", feed)
        sparse = [f"{subroot}/{p}" if subroot else p for p in configured]
        module.ensure_sparse_checkout(checkout, source, sparse)
        source_root = checkout / subroot if subroot else checkout
        module.ensure_source_link(sdk, feed, source_root)
        for path in sorted(paths):
            recipe = source_root / path
            if not (recipe / "Makefile").is_file():
                raise RuntimeError(f"Missing upstream recipe {feed}/{path}")
            dest = sdk / "package" / "feeds" / feed / recipe.name
            dest.parent.mkdir(parents=True, exist_ok=True)
            if dest.is_symlink() or dest.is_file():
                dest.unlink()
            elif dest.is_dir():
                shutil.rmtree(dest)
            dest.symlink_to(recipe, target_is_directory=True)
            recipe_targets[(feed, path)] = f"package/feeds/{feed}/{recipe.name}/compile"
    return recipe_targets



def stage_official_link_libraries(sdk, cache, release, arch, packages):
    """Stage link-only stubs built from exact official release APK symbols."""
    target_dirs = list((sdk / "staging_dir").glob("target-*"))
    tools = list((sdk / "staging_dir").glob("toolchain-*/bin/*-readelf"))
    pairs = {}
    for readelf in tools:
        cc = readelf.with_name(readelf.name.removesuffix("readelf") + "gcc")
        if cc.exists():
            pairs[(str(readelf.resolve()), str(cc.resolve()))] = (readelf, cc)
    if len(target_dirs) != 1 or len(pairs) != 1:
        raise RuntimeError("Cannot unambiguously identify target SDK staging/toolchain")
    stage = target_dirs[0]
    readelf, cc = next(iter(pairs.values()))
    apk_tool = sdk / "staging_dir/host/bin/apk"
    libdir = stage / "usr/lib"
    libdir.mkdir(parents=True, exist_ok=True)
    for package, feed, pattern, linker_name in packages:
        url = subprocess.check_output(
            [sys.executable, str(ROOT / "scripts/resolve-openwrt-package.py"),
             release, arch, feed, package], text=True).strip()
        location = cache / "official-link-libraries" / release / arch / package
        location.mkdir(parents=True, exist_ok=True)
        archive = location / url.rsplit("/", 1)[-1]
        if not archive.exists():
            run("curl", "--fail", "--location", "--retry", "5",
                "--output", archive, url)
        extract = location / "extracted"
        if extract.exists():
            shutil.rmtree(extract)
        extract.mkdir()
        run(apk_tool, "--allow-untrusted", "extract",
            "--destination", extract, archive)
        matches = [candidate for candidate in extract.rglob(pattern)
                   if candidate.is_file()]
        if not matches and pattern.endswith(".so.*"):
            # Some OpenWrt ABI libraries ship an unversioned ELF filename.
            matches = [candidate for candidate in
                       extract.rglob(pattern.removesuffix(".*"))
                       if candidate.is_file()]
        # Versioned libraries often contain both the SONAME symlink
        # (libfaad.so.2) and its real ELF (libfaad.so.2.11.1).
        # Resolve those aliases before enforcing a unique library.
        resolved = {candidate.resolve() for candidate in matches}
        if len(resolved) != 1:
            available = sorted(str(candidate.relative_to(extract))
                               for candidate in extract.rglob("*.so*")
                               if candidate.is_file())
            raise RuntimeError(
                f"Expected one ELF behind {pattern} in {archive}: {matches}; "
                f"resolved paths: {sorted(map(str, resolved))}; "
                f"available shared libraries: {available}")
        lib = next(iter(resolved))
        dynamic = subprocess.check_output([str(readelf), "-d", str(lib)], text=True)
        soname_match = re.search(r"\(SONAME\).*?\[([^]]+)\]", dynamic)
        soname = soname_match.group(1) if soname_match else lib.name
        run(sys.executable, ROOT / "scripts/create-elf-link-stub.py",
            readelf, cc, lib, libdir / linker_name, soname)
        if soname != linker_name:
            alias = libdir / soname
            if alias.exists() or alias.is_symlink():
                alias.unlink()
            alias.symlink_to(linker_name)
        for name in {package, re.sub(r"-[0-9].*$", "", archive.stem)}:
            provides = stage / "pkginfo" / f"{name}.provides"
            provides.parent.mkdir(parents=True, exist_ok=True)
            with provides.open("a") as out:
                out.write(soname + "\n")

def stage_official_bluetooth_modules(sdk, cache, release, target, subtarget):
    """Reuse exact-release signed Bluetooth kernel modules; never rebuild Linux."""
    metadata = json.loads(subprocess.check_output([
        sys.executable, str(ROOT / "scripts/resolve-openwrt-artifacts.py"),
        release, target, subtarget,
    ], text=True))
    workspace = cache / "official-bluetooth" / release / target / subtarget
    workspace.mkdir(parents=True, exist_ok=True)
    manifest = workspace / "sha256sums"
    if not manifest.is_file():
        run("curl", "--fail", "--location", "--retry", "5",
            "--output", manifest, metadata["kmods_sha256sums_url"])
    # The feed is a src-link to the checked-out repository. Materialize a
    # private SDK-local recipe so build preparation never modifies the checkout.
    recipe = sdk / "package/feeds/audiowrt/kmod-bluetooth-tailored"
    source = ROOT / "tailored/kmod-bluetooth-tailored"
    private_recipe = sdk / "audiowrt-generated/kmod-bluetooth-tailored"
    private_recipe.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, private_recipe, dirs_exist_ok=True)
    if recipe.is_symlink() or recipe.is_file():
        recipe.unlink()
    elif recipe.is_dir():
        shutil.rmtree(recipe)
    recipe.symlink_to(private_recipe, target_is_directory=True)
    module_dir = private_recipe / "files"
    module_dir.mkdir(parents=True, exist_ok=True)
    for existing in module_dir.glob("*.ko"):
        existing.unlink()
    extracted = workspace / "extracted"
    if extracted.exists():
        shutil.rmtree(extracted)
    extracted.mkdir()
    apk_tool = sdk / "staging_dir/host/bin/apk"
    for key in ("kmod_bluetooth_url", "kmod_btmtk_url", "kmod_btusb_url"):
        url = metadata[key]
        archive = workspace / url.rsplit("/", 1)[-1]
        if not archive.is_file():
            run("curl", "--fail", "--location", "--retry", "5",
                "--output", archive, url)
        relative = url.removeprefix(metadata["base_url"])
        if relative == url:
            raise RuntimeError(f"Bluetooth APK outside release target: {url}")
        run(sys.executable, ROOT / "scripts/verify-openwrt-checksum.py",
            manifest, relative, archive)
        run(apk_tool, "--allow-untrusted", "extract",
            "--destination", extracted, archive)
    for name in ("bluetooth.ko", "btmtk.ko", "btintel.ko", "btrtl.ko", "btusb.ko"):
        matches = [p for p in extracted.rglob(name) if p.is_file()]
        if len(matches) != 1:
            raise RuntimeError(f"Expected exactly one official {name}; found {len(matches)}")
        shutil.copy2(matches[0], module_dir / name)
    for forbidden in ("rfcomm.ko", "bnep.ko", "hidp.ko"):
        if (module_dir / forbidden).exists():
            raise RuntimeError(f"Disallowed Bluetooth module: {forbidden}")
    print("Staged five verified, exact-release Bluetooth .ko modules", flush=True)


def sanitize_cross_meson_includes(sdk):
    """Remove Docker host include paths and host zlib from target GLib Ninja rules."""
    builds = list((sdk / "build_dir").glob("target-*/glib-*/openwrt-build/build.ninja"))
    if len(builds) != 1:
        raise RuntimeError(f"Expected one configured target GLib Ninja build: {builds}")
    ninja = builds[0]
    original = ninja.read_text()
    sanitized = re.sub(r"(?<!\\S)-I/usr/include(?=\\s|$)", "", original, flags=re.M)
    host_zlib = str(sdk / "staging_dir/host/lib/libz.a")
    if host_zlib in sanitized:
        targets = list((sdk / "staging_dir").glob("target-*/usr/lib/libz.so"))
        if len(targets) != 1 or not targets[0].exists():
            raise RuntimeError(f"Host zlib leaked into GLib, but target zlib missing: {targets}")
        sanitized = sanitized.replace(host_zlib, str(targets[0]))
    if sanitized != original:
        ninja.write_text(sanitized)
        print(f"Sanitized GLib host paths in {ninja}", flush=True)
    if re.search(r"(?<!\\S)-I/usr/include(?=\\s|$)", sanitized, re.M) or host_zlib in sanitized:
        raise RuntimeError("GLib cross build still contains host development paths")


def development_recipes(dependencies):
    recipes = []
    for dep in dependencies:
        name = dep.split("/", 1)[0]
        if name == "glib2":
            recipes += [
                ("base", "libs/zlib"), ("base", "libs/pcre2"),
                ("packages", "libs/libffi"), ("packages", "utils/attr"),
                ("packages", "libs/glib2"),
            ]
        elif name == "openssl":
            recipes.append(("base", "libs/openssl"))
        elif name == "rust":
            recipes.append(("packages", "lang/rust"))
        else:
            raise RuntimeError(f"Unsupported build dependency: {dep}")
    return list(dict.fromkeys(recipes))


@contextmanager
def sdk_workspace(archive, cache, persistent=False):
    """Keep expensive host Rust/Cargo and target artifacts across invocations.

    A per-SDK lock prevents parallel writers corrupting the same staging tree.
    Other packages keep their previous isolated temporary SDK behavior.
    """
    if not persistent:
        with tempfile.TemporaryDirectory(prefix="audiowrt-sdk-") as temp:
            yield sdk_root(archive, Path(temp))
        return

    workspace = cache / "sdk-workspaces" / archive.name
    workspace.mkdir(parents=True, exist_ok=True)
    with (workspace / ".lock").open("w") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        ready = workspace / ".ready"
        if not ready.exists():
            # Do not reuse a partial extraction after an interrupted build.
            for path in workspace.iterdir():
                if path.name == ".lock":
                    continue
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
            sdk_root(archive, workspace)
            ready.touch()
        roots = [p for p in workspace.iterdir() if p.is_dir()]
        if len(roots) != 1:
            raise RuntimeError(f"Unexpected SDK workspace layout: {workspace}")
        yield roots[0]


def compile_sdk(args):
    sources = package_sources()
    targets = package_map()
    unknown = set(args.package) - targets.keys()
    if unknown:
        raise RuntimeError(f"Unknown package names: {sorted(unknown)}")
    cache = (ROOT / args.cache_dir).resolve()
    output = (ROOT / args.output).resolve()
    cache.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    archive = download_sdk(args.release, args.target, args.subtarget, cache)
    with sdk_workspace(archive, cache, persistent="librespot" in args.package) as sdk:
        # Match the proven AudioWRT SDK sequence at 8eb72f8: retain the
        # release-pinned feeds, update packages + LuCI, and use this checkout
        # as the local AudioWRT feed without cloning the firmware repository.
        (sdk / "feeds.conf").write_text(
            (sdk / "feeds.conf.default").read_text() +
            f"\nsrc-link audiowrt {ROOT}\n"
        )
        feeds_to_update = [
            feed for feed in ("packages", "luci", "audiowrt")
            if not (sdk / "feeds" / feed).exists()
        ]
        if feeds_to_update:
            run("./scripts/feeds", "update", *feeds_to_update, cwd=sdk)
        links = sdk / "package/feeds/audiowrt"
        links.mkdir(parents=True, exist_ok=True)
        for name, target_path in targets.items():
            if not target_path.startswith("package/feeds/audiowrt/"):
                continue
            source = sources.get(name)
            if source is None:
                continue
            entry = links / target_path.split("/")[3]
            if not entry.exists() and not entry.is_symlink():
                entry.symlink_to(source, target_is_directory=True)
        if "kmod-bluetooth-tailored" in args.package:
            # Register the SDK-local binary-repackaging recipe before Make
            # generates .packageinfo and make targets.
            stage_official_bluetooth_modules(sdk, cache, args.release, args.target, args.subtarget)
        run("make", f"VERSION_NUMBER={args.release}", "-s", "prepare-tmpinfo", cwd=sdk)
        config = sdk / ".config"
        with config.open("a") as stream:
            for package in args.package:
                stream.write(f"CONFIG_PACKAGE_{package}=m\n")
        run("make", f"VERSION_NUMBER={args.release}", "defconfig", cwd=sdk)
        info = sdk / "tmp/.packageinfo"
        plan = subprocess.check_output([
            sys.executable, str(ROOT / "scripts/resolve-package-build-targets.py"),
            str(ROOT / "config/build/package-build-targets"),
            str(info), *args.package, "--providers", *targets.keys()
        ], text=True)
        specs = [row.split("|", 1) for row in plan.splitlines() if "|" in row]
        if not specs:
            raise RuntimeError("No build targets resolved")
        selected = list(dict.fromkeys(package for package, _ in specs))
        source_set = {
            line.strip() for line in (ROOT / "config/build/source-build-packages").read_text().splitlines()
            if line.strip() and not line.startswith("#")
        }
        config_flags = [f"CONFIG_PACKAGE_{p}=m" for p in selected]
        run("make", f"VERSION_NUMBER={args.release}", "package/toolchain/compile",
            "NO_DEPS=1", f"-j{args.jobs}", cwd=sdk)
        source_roots = [p for p in selected if p in source_set]
        if source_roots:
            deps = subprocess.check_output([
                sys.executable, str(ROOT / "scripts/resolve-source-build-dependencies.py"),
                str(ROOT / "config/build/package-build-targets"), str(info),
                *source_roots, "--providers", *selected
            ], text=True).splitlines()
            # Compile only genuine development dependencies; refuse implicit
            # dependency expansion rather than rebuilding arbitrary official feeds.
            if deps:
                print("Explicit development dependencies:", deps, flush=True)
                supported = {"glib2", "dbus", "openssl", "rust"}
                unexpected = {d.split("/")[0] for d in deps} - supported
                if unexpected:
                    raise RuntimeError(f"Dependency staging needs an explicit rule: {sorted(unexpected)}")
                # Stage official development providers and pkginfo metadata
                # before compiling package-only trimmed runtime packages.
                # BlueZ requires dbus-1.pc and glib2-trimmed's dependency
                # checker needs libffi/pcre2/zlib .provides entries.
                if not (sdk / "feeds/base").exists():
                    run("./scripts/feeds", "update", "base", cwd=sdk)
                # rust/host is a build dependency identifier, not a feed
                # package name. Register the actual Rust recipe and regenerate
                # package metadata before invoking its host build target.
                feed_packages = [d.split("/", 1)[0] for d in deps
                                 if d.split("/", 1)[0] != "openssl"]
                if feed_packages:
                    run("./scripts/feeds", "install", *dict.fromkeys(feed_packages), cwd=sdk)
                # The SDK does not provide package recipes for base
                # libraries. GLib needs these real target/host providers,
                # including pcre2/host and libiconv-full/host. Register their
                # pinned base recipes before resolving Make dependencies.
                if "glib2" in deps:
                    glib_base_targets = register_upstream_sdk_sources(sdk, cache, [
                        ("base", "libs/zlib"),
                        ("base", "libs/pcre2"),
                        ("base", "libs/libiconv-full"),
                        ("base", "libs/gettext-full"),
                    ])
                # Base OpenSSL is an SDK source recipe, not a packages-feed
                # entry. Stage its real development files for openssl-sys.
                if "openssl" in deps:
                    openssl_recipe = ("base", "libs/openssl")
                    openssl_targets = register_upstream_sdk_sources(
                        sdk, cache, [openssl_recipe])
                    openssl_target = openssl_targets[openssl_recipe]
                run("make", f"VERSION_NUMBER={args.release}", "-s",
                    "prepare-tmpinfo", cwd=sdk)
                run("make", f"VERSION_NUMBER={args.release}", "defconfig", cwd=sdk)
                # The SDK contains runtime toolchains, not the build-time
                # development interfaces for GLib/D-Bus or host Rust/Cargo.
                # Build only explicitly requested development providers,
                # before building their AudioWRT consumers. The SDK controls
                # the target ABI; do not replace Cargo with the host distro
                # version or fake .pc files lacking headers/libraries.
                development_targets = {
                    "glib2": "package/feeds/packages/glib2/compile",
                    "dbus": "package/feeds/packages/dbus/compile",
                    "rust/host": "package/feeds/packages/rust/host/compile",
                    "openssl": openssl_target if "openssl" in deps else None,
                }
                if "glib2" in deps:
                    # An empty CI SDK lacks zlib and libffi development files.
                    # Build target providers first, before Meson configures
                    # GLib, so it does not use unsupported fallback subprojects.
                    for provider in (
                        glib_base_targets[("base", "libs/zlib")],
                        "package/feeds/packages/libffi/compile",
                    ):
                        print(f"Staging GLib target dependency: {provider}", flush=True)
                        run("make", f"VERSION_NUMBER={args.release}",
                            "CONFIG_PACKAGE_kmod-bluetooth=n",
                            "CONFIG_PACKAGE_kmod-bluetooth-tailored=n",
                            provider, "-j1", "V=s", cwd=sdk)
                for dep in dict.fromkeys(deps):
                    target = development_targets.get(dep)
                    if target is None:
                        raise RuntimeError(f"No development target for {dep}")
                    print(f"Preparing real SDK development dependency: {dep}", flush=True)
                    # Host Rust builds are unusually large and SDK's top-level
                    # parallel make hides the underlying failure. Force a
                    # single verbose invocation for actionable diagnostics.
                    extra = ["-j1", "V=s"] if dep in {"rust/host", "openssl", "glib2", "dbus"} else [
                        f"-j{args.jobs}"]
                    openssl_flags = [
                        # OpenWrt's recipe enables devcryptoeng when any of
                        # these options is nonempty. Librespot needs only the
                        # SSL/crypto libraries, not optional kernel engines.
                        "CONFIG_OPENSSL_ENGINE=",
                        "CONFIG_OPENSSL_ENGINE_BUILTIN_DEVCRYPTO=",
                        "CONFIG_PACKAGE_libopenssl-devcrypto=",
                        "CONFIG_PACKAGE_libopenssl-afalg=",
                        "CONFIG_PACKAGE_libopenssl-padlock=",
                    ] if dep == "openssl" else []
                    if dep == "openssl":
                        # The persistent SDK may already contain an OpenSSL
                        # configure stamp with devcryptoeng enabled. Clean
                        # that package only, once, before changing options.
                        marker = sdk / ".audiowrt-openssl-no-engines"
                        if not marker.exists():
                            run("make", f"VERSION_NUMBER={args.release}",
                                target.removesuffix("/compile") + "/clean",
                                "NO_DEPS=1", "-j1", cwd=sdk)
                    if dep == "glib2":
                        # Configure first, so Meson's Ninja output can be
                        # checked before any MIPS compiler invocation.
                        run("make", f"VERSION_NUMBER={args.release}",
                            "CONFIG_PACKAGE_kmod-bluetooth=n",
                            "CONFIG_PACKAGE_kmod-bluetooth-tailored=n",
                            target.removesuffix("/compile") + "/configure",
                            "-j1", "V=s", cwd=sdk)
                        # OpenWrt may retain .configured stamps after its
                        # autoremove step deletes the Meson build directory.
                        # A no-op /configure is then not a valid configuration.
                        ninja_files = list((sdk / "build_dir").glob(
                            "target-*/glib-*/openwrt-build/build.ninja"))
                        if len(ninja_files) != 1:
                            print("GLib configuration stamp is stale; "
                                  "cleaning only GLib and configuring again", flush=True)
                            run("make", f"VERSION_NUMBER={args.release}",
                                target.removesuffix("/compile") + "/clean",
                                "NO_DEPS=1", "-j1", cwd=sdk)
                            run("make", f"VERSION_NUMBER={args.release}",
                                "CONFIG_PACKAGE_kmod-bluetooth=n",
                                "CONFIG_PACKAGE_kmod-bluetooth-tailored=n",
                                target.removesuffix("/compile") + "/configure",
                                "-j1", "V=s", cwd=sdk)
                        sanitize_cross_meson_includes(sdk)
                    run("make", f"VERSION_NUMBER={args.release}",
                        "CONFIG_PACKAGE_kmod-bluetooth=n",
                        "CONFIG_PACKAGE_kmod-bluetooth-tailored=n",
                        *openssl_flags, target,
                        *(["NO_DEPS=1"] if dep == "openssl" else []),
                        *extra, cwd=sdk)
                    if dep == "openssl":
                        marker.touch()
                    if dep == "openssl":
                        stages = list((sdk / "staging_dir").glob("target-*/usr/lib/pkgconfig/openssl.pc"))
                        if len(stages) != 1 or not stages[0].is_file():
                            raise RuntimeError("OpenSSL compiled but openssl.pc was not staged: "
                                               + str(stages))
                if "rust/host" in deps:
                    # Rust's OpenWrt host recipe installs into target-*/host,
                    # not staging_dir/host (the generic SDK host tools).
                    rust_hosts = list((sdk / "staging_dir").glob("target-*/host/bin/cargo"))
                    if len(rust_hosts) != 1 or not rust_hosts[0].is_file():
                        raise RuntimeError(
                            "OpenWrt Rust host recipe finished but expected exactly "
                            f"one Cargo under staging_dir/target-*/host/bin: {rust_hosts}")
                    print(f"Using OpenWrt Cargo: {rust_hosts[0]}", flush=True)
        # Prepare SDK development interfaces for native players and WPA.
        # The original AudioWRT builder 8eb72f8 explicitly staged these
        # providers before compiling consumers. The standalone SDK does not
        # ship their public headers by default.
        native_players = {
            "libaudiowrt-player", "audiowrt-player-flac",
            "audiowrt-player-mp3", "audiowrt-player-aac",
            "audiowrt-player-m4a", "audiowrt-player-vorbis",
            "audiowrt-player-opus", "audiowrt-player-wav",
            "audiowrt-player-aiff", "audiowrt-player-lpcm",
            "audiowrt-player-ffmpeg",
        }
        hostap_packages = {"hostapd-wpa-supplicant-tailored"}
        native_selected = native_players.intersection(selected)
        hostap_selected = hostap_packages.intersection(selected)
        sdk_providers = []
        if native_selected or hostap_selected:
            sdk_providers += [
                ("base", "libs/libubox"), ("base", "libs/uclient"),
                ("base", "libs/ustream-ssl"),
            ]
        if "bluez-alsa" in selected:
            sdk_providers.append(("packages", "utils/bluez"))
        if "luci-mod-status-tailored" in selected:
            sdk_providers += [("base", "network/utils/iwinfo"),
                              ("base", "system/uci"),
                              ("base", "system/ubus"),
                              ("base", "libs/libubox")]
        if hostap_selected:
            sdk_providers += [
                ("base", "libs/libnl-tiny"), ("base", "libs/libjson-c"),
                ("base", "libs/mbedtls"), ("base", "system/ubus"),
                ("base", "utils/ucode"), ("base", "libs/udebug"),
            ]
        player_sources = {
            "audiowrt-player-flac": ("packages", "libs/flac"),
            "audiowrt-player-mp3": ("packages", "libs/libmad"),
            "audiowrt-player-aac": ("packages", "libs/faad2"),
            "audiowrt-player-m4a": ("packages", "libs/faad2"),
            "audiowrt-player-vorbis": ("packages", "libs/libvorbis"),
            "audiowrt-player-opus": ("packages", "libs/opusfile"),
        }
        for player, source in player_sources.items():
            if player in native_selected:
                sdk_providers.append(source)
                if player == "audiowrt-player-vorbis":
                    sdk_providers.append(("packages", "libs/libogg"))
                if player == "audiowrt-player-opus":
                    sdk_providers.append(("packages", "libs/opus"))
        if sdk_providers:
            sdk_providers = list(dict.fromkeys(sdk_providers))
            print("Preparing SDK development providers:", sdk_providers, flush=True)
            recipe_targets = register_upstream_sdk_sources(sdk, cache, sdk_providers)
            run("make", f"VERSION_NUMBER={args.release}", "defconfig", cwd=sdk)
            # The proven AudioWRT builder prepares official sources without
            # recompiling firmware runtime libraries (libubox, uclient, etc).
            # Do not blindly compile every provider: SDK source builds can
            # fail or change the ABI relative to the official release APKs.
            # Only compile the two development packages explicitly compiled
            # by the original hostap preparation path.
            for provider in sdk_providers:
                feed, source_path = provider
                target = recipe_targets[provider]
                if provider in {("base", "libs/libnl-tiny"),
                                ("base", "libs/libjson-c")}:
                    action = "compile"
                elif provider in {("packages", "libs/libmad"),
                                  ("base", "libs/mbedtls"),
                                  ("packages", "libs/libogg")}:
                    action = "configure"
                else:
                    action = "prepare"
                run("make", f"VERSION_NUMBER={args.release}",
                    target.removesuffix("/compile") + "/" + action,
                    "NO_DEPS=1", f"-j{args.jobs}", cwd=sdk)
        # Match the header staging step of the known-good firmware builder.
        # 'prepare' only unpacks sources; it does NOT install headers into
        # staging_dir/target-*/usr/include on its own.
        if sdk_providers:
            staging_candidates = list((sdk / "staging_dir").glob("target-*"))
            if len(staging_candidates) != 1:
                raise RuntimeError(f"Expected exactly one target staging directory: {staging_candidates}")
            staging = staging_candidates[0]
            headers = staging / "usr/include"
            for feed, source_path in sdk_providers:
                package_name = Path(source_path).name
                build_sources = list((sdk / "build_dir").glob(f"target-*/{package_name}-*"))
                if package_name == "bluez":
                    # BlueZ public API headers live under lib/ in its source,
                    # but consumers include them as <bluetooth/*.h>.
                    candidates = [root / "lib" for root in build_sources
                                  if (root / "lib/bluetooth.h").is_file()]
                    if len(candidates) != 1:
                        raise RuntimeError(f"Cannot locate BlueZ public headers: {candidates}")
                    dest = headers / "bluetooth"
                    dest.mkdir(parents=True, exist_ok=True)
                    for header in candidates[0].glob("*.h"):
                        shutil.copy2(header, dest / header.name)
                elif package_name == "iwinfo":
                    # LuCI status' luci-bwc.c needs the iwinfo public API.
                    # The pinned iwinfo recipe may use a different build
                    # directory name from 'iwinfo-*'. Search all extracted
                    # SDK source trees before treating the header as missing.
                    candidates = sorted(set(
                        h for h in (sdk / "build_dir").rglob("iwinfo.h")
                        if h.is_file() and "host" not in h.parts
                    ))
                    if len(candidates) == 1:
                        source_header = candidates[0]
                        shutil.copy2(source_header, headers / "iwinfo.h")
                        # iwinfo.h includes <iwinfo/utils.h>; staging only
                        # the top-level header is insufficient.
                        source_subdir = source_header.parent / "iwinfo"
                        if source_subdir.is_dir():
                            destination = headers / "iwinfo"
                            destination.mkdir(parents=True, exist_ok=True)
                            for header in source_subdir.rglob("*.h"):
                                relative = header.relative_to(source_subdir)
                                target = destination / relative
                                target.parent.mkdir(parents=True, exist_ok=True)
                                shutil.copy2(header, target)
                    elif not candidates:
                        # LuCI may still fail, but missing optional development
                        # headers must not abort the other 42 package builds.
                        print("WARNING: iwinfo.h not staged; "
                              "luci-mod-status-tailored may fail", flush=True)
                    else:
                        raise RuntimeError(f"Ambiguous iwinfo headers: {candidates}")
                elif package_name == "uci":
                    # The iwinfo public API includes <uci.h>. Extract it
                    # from the pinned official UCI sources, without rebuilding
                    # the UCI runtime package.
                    candidates = [h for root in build_sources
                                  for h in root.rglob("uci.h") if h.is_file()]
                    if len(candidates) != 1:
                        raise RuntimeError(f"Expected one official uci.h: {candidates}")
                    shutil.copy2(candidates[0], headers / "uci.h")
                    # OpenWrt UCI uses CMake configure_file(uci_config.h.in).
                    # Both UCI_DEBUG and UCI_DEBUG_TYPECAST are OFF by default.
                    # Generate the matching header without configuring or
                    # compiling the official UCI runtime package.
                    templates = [h for root in build_sources
                                 for h in root.rglob("uci_config.h.in")
                                 if h.is_file()]
                    if len(templates) != 1:
                        raise RuntimeError(
                            f"Expected one pinned uci_config.h.in: {templates}")
                    generated = templates[0].read_text()
                    generated = generated.replace("#cmakedefine UCI_DEBUG 1",
                                                  "/* #undef UCI_DEBUG */")
                    generated = generated.replace(
                        "#cmakedefine UCI_DEBUG_TYPECAST 1",
                        "/* #undef UCI_DEBUG_TYPECAST */")
                    if "#cmakedefine" in generated:
                        raise RuntimeError("Unknown UCI CMake configuration directive")
                    (headers / "uci_config.h").write_text(generated)
                elif package_name == "libubox":
                    destination = headers / "libubox"
                    destination.mkdir(parents=True, exist_ok=True)
                    candidates = [h for root in build_sources for h in root.glob("*.h")]
                    if not candidates:
                        raise RuntimeError("libubox prepared source headers not found")
                    for header in candidates:
                        shutil.copy2(header, destination / header.name)
                    if not (destination / "avl.h").is_file() or not (destination / "uloop.h").is_file():
                        raise RuntimeError("libubox SDK headers incomplete")
                elif package_name == "uclient":
                    destination = headers / "libubox"
                    destination.mkdir(parents=True, exist_ok=True)
                    for root in build_sources:
                        for header in root.glob("*.h"):
                            shutil.copy2(header, destination / header.name)
                elif package_name == "ustream-ssl":
                    destination = headers / "libubox"
                    destination.mkdir(parents=True, exist_ok=True)
                    matches = [h for root in build_sources for h in root.rglob("ustream-ssl.h")]
                    if matches:
                        shutil.copy2(matches[0], destination / "ustream-ssl.h")
                elif package_name == "mbedtls" and hostap_selected:
                    candidates = [root / "include" for root in build_sources
                                  if (root / "include/mbedtls/version.h").is_file()
                                  and (root / "include/psa/crypto.h").is_file()]
                    if len(candidates) != 1:
                        raise RuntimeError(f"Cannot stage MbedTLS public headers: {candidates}")
                    for subdir in ("mbedtls", "psa"):
                        dest = headers / subdir
                        dest.mkdir(parents=True, exist_ok=True)
                        for header in (candidates[0] / subdir).glob("*.h"):
                            shutil.copy2(header, dest / header.name)
                elif package_name == "ucode" and hostap_selected:
                    # Ported from prepare_hostap_sdk() in AudioWRT 8eb72f8:
                    # libucode exports its API in include/ucode, not at the
                    # source root. Merely running prepare never stages it.
                    candidates = [root / "include/ucode" for root in build_sources
                                  if (root / "include/ucode/lib.h").is_file()]
                    if len(candidates) != 1:
                        raise RuntimeError(f"Cannot stage ucode/lib.h: {candidates}")
                    dest = headers / "ucode"
                    dest.mkdir(parents=True, exist_ok=True)
                    for header in candidates[0].glob("*.h"):
                        shutil.copy2(header, dest / header.name)
                elif package_name == "udebug" and hostap_selected:
                    candidates = [root / "udebug.h" for root in build_sources
                                  if (root / "udebug.h").is_file()]
                    if len(candidates) != 1:
                        raise RuntimeError(f"Cannot stage udebug.h: {candidates}")
                    headers.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(candidates[0], headers / "udebug.h")
                elif package_name == "ubus" and (hostap_selected or "luci-mod-status-tailored" in selected):
                    candidates = [h for root in build_sources
                                  for h in root.glob("libubus.h")]
                    if len(candidates) != 1:
                        raise RuntimeError(f"Cannot stage libubus.h: {candidates}")
                    headers.mkdir(parents=True, exist_ok=True)
                    for sibling in candidates[0].parent.glob("*.h"):
                        shutil.copy2(sibling, headers / sibling.name)
                elif package_name in {"faad2", "flac", "libmad",
                                      "opusfile", "libvorbis", "libogg", "opus"}:
                    # The SDK does not install public headers for packages
                    # whose source we only prepare. Stage the public API
                    # paths required by the native decoder recipes.
                    public = {
                        "faad2": ("neaacdec.h", "neaacdec.h"),
                        "flac": ("include/FLAC/stream_decoder.h", "FLAC/stream_decoder.h"),
                        "libmad": ("mad.h", "mad.h"),
                        "opusfile": ("include/opus/opusfile.h", "opus/opusfile.h"),
                        "libvorbis": ("include/vorbis/vorbisfile.h", "vorbis/vorbisfile.h"),
                        "libogg": ("include/ogg/ogg.h", "ogg/ogg.h"),
                        "opus": ("include/opus/opus.h", "opus/opus.h"),
                    }
                    source_suffix, destination_suffix = public[package_name]
                    candidates = [h for root in build_sources
                                  for h in root.rglob(Path(source_suffix).name)
                                  if h.is_file() and (source_suffix == h.name or
                                      h.as_posix().endswith("/" + source_suffix))]
                    # Some upstream trees generate public headers in their
                    # CMake build directory; prioritize the canonical include
                    # path instead of same-named private implementation files.
                    if not candidates:
                        candidates = [h for root in build_sources
                                      for h in root.rglob(Path(source_suffix).name)
                                      if h.is_file()]
                    if len(candidates) > 1:
                        candidates = sorted(candidates, key=lambda h: (
                            not h.as_posix().endswith("/" + source_suffix),
                            len(h.parts)))
                        candidates = candidates[:1]
                    if len(candidates) != 1:
                        # Header layouts can differ between upstream releases
                        # and some headers are generated during configure.
                        # This is an optional staging optimization: leave the
                        # package compiler to report its own failure instead
                        # of aborting every independent package task.
                        print(
                            f"WARNING: cannot stage {package_name} public header "
                            f"{source_suffix}: {candidates}; "
                            "continuing with remaining package tasks",
                            flush=True,
                        )
                        continue
                    # Copy the complete public include tree, not only the
                    # first header: FLAC/Vorbis/Opus headers include siblings.
                    public_header = candidates[0]
                    if package_name in {"flac", "opusfile", "libvorbis", "libogg", "opus"}:
                        relative_dir = Path(destination_suffix).parent
                        src_dir = public_header.parent
                        dest_dir = headers / relative_dir
                        dest_dir.mkdir(parents=True, exist_ok=True)
                        for sibling in src_dir.glob("*.h"):
                            shutil.copy2(sibling, dest_dir / sibling.name)
                        if package_name == "opus":
                            # opusfile.h includes <opus_multistream.h> without
                            # the opus/ prefix. OpenWrt's native decoder also
                            # expects the plain opus include search path.
                            for header in dest_dir.glob("*.h"):
                                shutil.copy2(header, headers / header.name)
                            # Some Opus releases put secondary public API
                            # headers outside the directory containing opus.h.
                            required = ("opus.h", "opus_types.h",
                                        "opus_defines.h", "opus_multistream.h")
                            for name in required:
                                if not (dest_dir / name).is_file():
                                    matches = [h for root in build_sources
                                               for h in root.rglob(name)
                                               if h.is_file() and "include" in h.parts]
                                    if len(matches) == 1:
                                        shutil.copy2(matches[0], dest_dir / name)
                                        shutil.copy2(matches[0], headers / name)
                                if not (dest_dir / name).is_file():
                                    raise RuntimeError(
                                        f"Opus public development header missing: {name}")
                        if package_name == "libogg":
                            generated = [h for root in build_sources
                                         for h in root.rglob("config_types.h")]
                            if generated:
                                shutil.copy2(generated[0], dest_dir / "config_types.h")
                    else:
                        dest = headers / destination_suffix
                        dest.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(public_header, dest)
        if native_selected:
            stage_official_link_libraries(sdk, cache, args.release, args.arch, [
                ("libubox", "base", "libubox.so.*", "libubox.so"),
                ("libuclient", "base", "libuclient.so.*", "libuclient.so"),
            ])
            codec_libraries = {
                "audiowrt-player-aac": [("libfaad2", "packages", "libfaad.so*", "libfaad.so")],
                "audiowrt-player-flac": [("libflac", "packages", "libFLAC.so*", "libFLAC.so")],
                "audiowrt-player-mp3": [("libmad", "packages", "libmad.so*", "libmad.so")],
                "audiowrt-player-vorbis": [("libvorbis", "packages", "libvorbisfile.so*", "libvorbisfile.so")],
                "audiowrt-player-opus": [("libopusfile", "packages", "libopusfile.so*", "libopusfile.so")],
            }
            requested_libraries = [library for package, libraries in codec_libraries.items()
                                   if package in native_selected for library in libraries]
            if requested_libraries:
                stage_official_link_libraries(sdk, cache, args.release, args.arch,
                                              requested_libraries)
        if "bluez-alsa" in selected:
            stage_official_link_libraries(sdk, cache, args.release, args.arch, [
                ("bluez-libs", "packages", "libbluetooth.so.*", "libbluetooth.so"),
            ])
        if hostap_selected:
            stage_official_link_libraries(sdk, cache, args.release, args.arch, [
                ("libblobmsg-json", "base", "libblobmsg_json.so.*", "libblobmsg_json.so"),
                ("libubus", "base", "libubus.so.*", "libubus.so"),
                ("libucode", "base", "libucode.so.*", "libucode.so"),
                ("libudebug", "base", "libudebug.so*", "libudebug.so"),
                ("libmbedtls21", "base", "libmbedcrypto.so.*", "libmbedcrypto.so"),
                ("libmbedtls21", "base", "libmbedx509.so.*", "libmbedx509.so"),
                ("libmbedtls21", "base", "libmbedtls.so.*", "libmbedtls.so"),
            ])
        # This SDK stages link-only ELF stubs. Packaging still checks every
        # binary's DT_NEEDED libraries against the provider metadata. Record
        # the SONAMEs against their real runtime packages; never disable the
        # dependency checker or pretend they are bundled in AudioWRT APKs.
        staging_dir = next(iter((sdk / "staging_dir").glob("target-*")))
        pkginfo = staging_dir / "pkginfo"
        pkginfo.mkdir(parents=True, exist_ok=True)
        required_sonames = {
            "libmbedtls": ("libmbedcrypto.so.16", "libmbedtls.so.21",
                           "libmbedx509.so.7"),
            "libjson-c": ("libjson-c.so.5",),
            "glib2-trimmed": ("libgio-2.0.so.0", "libglib-2.0.so.0",
                             "libgobject-2.0.so.0"),
            "sbc-trimmed": ("libsbc.so.1",),
            "kmod-usb-core": ("usbcore.ko",),
            # ABI names are from the exact OpenWrt release APKs; record
            # them for OpenWrt's package dependency scanner without building
            # official libraries just for the trimmed APK repackaging.
            "libffi": ("libffi.so.8",),
            "libpcre2": ("libpcre2-8.so.0",),
            "zlib": ("libz.so.1",),
            "libdbus": ("libdbus-1.so.3",),
            "libexpat": ("libexpat.so.1",),
            # The five verified official Bluetooth objects depend on these
            # separate official kmods. Their APKs remain external runtime
            # dependencies; pkginfo only tells the SDK package scanner which
            # package supplies each imported kernel object.
            "kmod-lib-crc16": ("crc16.ko",),
            "kmod-crypto-ecdh": ("ecdh_generic.ko",),
            "kmod-crypto-kpp": ("kpp.ko",),
        }
        for provider, sonames in required_sonames.items():
            provide_file = pkginfo / f"{provider}.provides"
            existing = set(provide_file.read_text().splitlines()) if provide_file.exists() else set()
            provide_file.write_text("\n".join(sorted(existing.union(sonames))) + "\n")
        errors = []
        # Download selected packages separately with NO_DEPS, as in 8eb72f8.
        # The Bluetooth kernel modules were already downloaded from the
        # exact-release official APKs and checksum-verified above. There is
        # no upstream source archive to fetch for this repackaging recipe.
        download_targets = list(dict.fromkeys(
            target.removesuffix("/compile") + "/download"
            for name, target in specs if name != "kmod-bluetooth-tailored"
        ))
        if download_targets:
            run("make", f"VERSION_NUMBER={args.release}", *config_flags,
                *download_targets, "NO_DEPS=1", f"-j{args.jobs}", cwd=sdk)
        for target_path in dict.fromkeys(target for _, target in specs):
            names = [name for name, path in specs if path == target_path]
            print(f"Compiling {', '.join(names)}", flush=True)
            try:
                source_target = any(name in source_set for name in names)
                # Recompute the active dependency closure per target; selected
                # providers unrelated to this target must not leak into it.
                target_plan = subprocess.check_output([
                    sys.executable, str(ROOT / "scripts/resolve-package-build-targets.py"),
                    str(ROOT / "config/build/package-build-targets"), str(sdk / "tmp/.packageinfo"),
                    *names, "--providers", *selected
                ], text=True)
                active = {row.split("|", 1)[0] for row in target_plan.splitlines() if "|" in row}
                target_flags = [f"CONFIG_PACKAGE_{name}={'m' if name in active else 'n'}"
                                for name in selected]
                run("make", f"VERSION_NUMBER={args.release}", *target_flags,
                    "CONFIG_PACKAGE_kmod-bluetooth=n",
                    *(["CONFIG_PACKAGE_kmod-bluetooth-tailored=m"]
                      if "kmod-bluetooth-tailored" in names
                      else ["CONFIG_PACKAGE_kmod-bluetooth-tailored=n"]),
                    target_path,
                    # Never rebuild official D-Bus/OpenSSL transitively.
                    # BlueZ/BlueALSA use staged official SDK interfaces;
                    # librespot still requires its host Rust toolchain.
                    # Match AudioWRT@8eb72f8: only the four explicit source
                    # targets follow their development dependency graph.
                    # Disable official/custom Bluetooth kmods for source builds
                    # without disabling their own userspace package symbols.
                    # BlueZ/BlueALSA and the Rust host toolchain must never
                    # force the full Linux kernel build through a prebuilt
                    # Bluetooth kmod dependency. The SDK has explicit
                    # development-interface preparation above.
                    *([] if source_target and not
                       ({"bluez-alsa", "bluez-trimmed", "librespot"} & set(names))
                       else ["NO_DEPS=1"]),
                    f"-j{args.jobs}", "V=s", cwd=sdk)
            except subprocess.CalledProcessError:
                errors += names
        produced = {}
        for package in args.package:
            source = sources.get(package)
            if not source:
                errors.append(package)
                continue
            content = (source / "Makefile").read_text()
            names = re.findall(r"^define Package/([^\s]+)", content, re.M)
            names += ["kmod-" + name for name in re.findall(r"^define KernelPackage/([^\s]+)", content, re.M)]
            destination = output / package / args.release / args.arch / args.target / args.subtarget
            apk_dir = destination / "packages"
            apk_dir.mkdir(parents=True, exist_ok=True)
            copied = []
            for name in names:
                for apk in (sdk / "bin").rglob(f"{name}-*.apk"):
                    shutil.copy2(apk, apk_dir / apk.name)
                    copied.append(apk.name)
            if copied:
                (destination / "context.json").write_text(json.dumps({
                    "package_source": package, "openwrt_version": args.release,
                    "arch": args.arch, "target": args.target, "subtarget": args.subtarget,
                }, indent=2) + "\n")
                produced[package] = copied
            else:
                errors.append(package)
        print(json.dumps({"produced": produced, "failed": sorted(set(errors))}, indent=2))
        return 1 if errors else 0

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", required=True)
    parser.add_argument("--arch", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--subtarget", required=True)
    parser.add_argument("--package", action="append", required=True)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--cache-dir", default=".cache/audiowrt-packages")
    parser.add_argument("--output", default="output/local")
    return compile_sdk(parser.parse_args())

if __name__ == "__main__":
    sys.exit(main())
