#!/usr/bin/env python3
"""Standalone OpenWrt SDK package compiler (no firmware profiles).

Port of the package-only phase of the AudioWRT SDK build: the repository owns
the package graph, the official SDK supplies the cross compiler and dependencies,
and only requested package roots are compiled. No AudioWRT checkout is used.
"""
from __future__ import annotations

import argparse
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
    with tempfile.TemporaryDirectory(prefix="audiowrt-sdk-") as temp:
        sdk = sdk_root(archive, Path(temp))
        # Match the proven AudioWRT SDK sequence at 8eb72f8: retain the
        # release-pinned feeds, update packages + LuCI, and use this checkout
        # as the local AudioWRT feed without cloning the firmware repository.
        (sdk / "feeds.conf").write_text(
            (sdk / "feeds.conf.default").read_text() +
            f"\nsrc-link audiowrt {ROOT}\n"
        )
        run("./scripts/feeds", "update", "packages", "luci", "audiowrt", cwd=sdk)
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
                run("./scripts/feeds", "update", "base", cwd=sdk)
                run("./scripts/feeds", "install", *deps, cwd=sdk)
                run("make", f"VERSION_NUMBER={args.release}", "defconfig", cwd=sdk)
                # Allow OpenWrt to resolve the development closure. Running
                # NO_DEPS here would suppress Build/InstallDev metadata.
                for dep in dict.fromkeys(d.split("/", 1)[0] for d in deps):
                    feed = "base" if dep == "openssl" else "packages"
                    target = f"package/feeds/{feed}/{dep}/compile"
                    run("make", f"VERSION_NUMBER={args.release}",
                        "CONFIG_PACKAGE_kmod-bluetooth=n",
                        "CONFIG_PACKAGE_kmod-bluetooth-tailored=n",
                        target, f"-j{args.jobs}", cwd=sdk)
        errors = []
        # Download selected packages separately with NO_DEPS, as in 8eb72f8.
        download_targets = list(dict.fromkeys(
            target.removesuffix("/compile") + "/download" for _, target in specs
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
                    "CONFIG_PACKAGE_kmod-bluetooth-tailored=n",
                    target_path,
                    *([] if source_target else ["NO_DEPS=1"]),
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
