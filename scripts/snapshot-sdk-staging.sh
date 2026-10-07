#!/usr/bin/env bash
# Snapshot SDK staging helpers copied from demonccc/audiowrt scripts/build.sh @ 680f766

prepare_bluetooth_package() {
bluetooth_module_source="${AUDIOWRT_BLUETOOTH_SOURCE_DIR:-$sdk_dir/feeds/audiowrt/kmod-bluetooth-tailored}"
bluetooth_cache="${AUDIOWRT_BLUETOOTH_CACHE_DIR:-}"
bluetooth_modules=(bluetooth.ko btmtk.ko btintel.ko btrtl.ko btusb.ko)

[[ -d "$bluetooth_module_source" ]] || {
    echo "ERROR: AudioWRT tailored Bluetooth kernel package source is missing." >&2
    exit 5
}
mkdir -p "$bluetooth_module_source/files"

cache_complete=0
if [[ -n "$bluetooth_cache" ]]; then
    cache_complete=1
    for module in "${bluetooth_modules[@]}"; do
        [[ -s "$bluetooth_cache/$module" ]] || {
            cache_complete=0
            break
        }
    done
fi

if (( cache_complete )); then
    echo "Bluetooth module cache hit: $release / $target/$subtarget"
    cp -f "$bluetooth_cache"/*.ko "$bluetooth_module_source/files/"
else
    bluetooth_stage="$work_dir/prebuilt-bluetooth-modules"
    rm -rf "$bluetooth_stage"
    mkdir -p "$bluetooth_stage/apks" "$bluetooth_stage/extracted"
    download_file "$kmods_sha256sums_url" "$bluetooth_stage/sha256sums"

    for module_url in "$kmod_bluetooth_url" "$kmod_btmtk_url" "$kmod_btusb_url"; do
        module_apk="$bluetooth_stage/apks/$(basename "$module_url")"
        download_file "$module_url" "$module_apk"
        module_path="${module_url#"$openwrt_base_url"}"
        [[ "$module_path" != "$module_url" && -n "$module_path" ]] || {
            echo "ERROR: kernel module URL is outside the OpenWrt target: $module_url" >&2
            exit 5
        }
        python3 "$repo_root/scripts/verify-openwrt-checksum.py" \
            "$bluetooth_stage/sha256sums" "$module_path" "$module_apk"
        "$sdk_dir/staging_dir/host/bin/apk" --allow-untrusted extract \
            --destination "$bluetooth_stage/extracted" "$module_apk"
    done

    for module in "${bluetooth_modules[@]}"; do
        mapfile -t module_matches < <(find "$bluetooth_stage/extracted" -type f -name "$module" -print)
        [[ "${#module_matches[@]}" -eq 1 ]] || {
            echo "ERROR: expected one exact-release $module, found ${#module_matches[@]}." >&2
            exit 5
        }
        cp -f "${module_matches[0]}" "$bluetooth_module_source/files/$module"
    done

    if [[ -n "$bluetooth_cache" ]]; then
        bluetooth_cache_tmp="$bluetooth_cache.tmp.$"
        rm -rf "$bluetooth_cache_tmp"
        mkdir -p "$bluetooth_cache_tmp"
        cp -f "$bluetooth_module_source/files"/*.ko "$bluetooth_cache_tmp/"
        cat > "$bluetooth_cache_tmp/SOURCE" <<EOF
OPENWRT_RELEASE=$release
TARGET=$target
SUBTARGET=$subtarget
KMOD_BLUETOOTH_URL=$kmod_bluetooth_url
KMOD_BTMTK_URL=$kmod_btmtk_url
KMOD_BTUSB_URL=$kmod_btusb_url
EOF
        rm -rf "$bluetooth_cache"
        mkdir -p "$(dirname "$bluetooth_cache")"
        mv "$bluetooth_cache_tmp" "$bluetooth_cache"
        echo "Bluetooth module cache stored: $bluetooth_cache"
    fi
fi

for omitted in rfcomm.ko bnep.ko hidp.ko; do
    [[ ! -e "$bluetooth_module_source/files/$omitted" ]] || {
        echo "ERROR: omitted Bluetooth module leaked into AudioWRT package: $omitted" >&2
        exit 5
    }
done
}

stage_official_runtime_provides() {
    local package="$1"
    local target_staging="$2"
    local package_stage="$work_dir/runtime-providers/$package"
    local repositories_file="$work_dir/runtime-repositories.list"
    local package_apk readelf_bin runtime_pkg soname library
    local -a readelf_candidates=() libraries=() fetched_apks=()

    if [[ ! -s "$repositories_file" ]]; then
        : > "$repositories_file"
        local feed base
        for feed in base packages luci routing telephony video; do
            if [[ "$release" == "snapshot" ]]; then
                base="https://downloads.openwrt.org/snapshots/packages/$arch_packages/$feed"
            else
                base="https://downloads.openwrt.org/releases/$release/packages/$arch_packages/$feed"
            fi
            printf '%s/packages.adb\n' "$base" >> "$repositories_file"
        done
    fi

    rm -rf "$package_stage"
    mkdir -p "$package_stage/extracted" "$package_stage/cache"
    if ! "$sdk_dir/staging_dir/host/bin/apk" \
        --allow-untrusted \
        --repositories-file "$repositories_file" \
        --cache-dir "$package_stage/cache" \
        --update-cache \
        fetch --no-progress -o "$package_stage" "$package"; then
        echo "Runtime provider metadata not required/available from global feeds: $package"
        return 0
    fi

    mapfile -t fetched_apks < <(find "$package_stage" -maxdepth 1 -type f -name '*.apk' -print)
    [[ "${#fetched_apks[@]}" -eq 1 ]] || {
        echo "ERROR: expected one fetched APK for $package, found ${#fetched_apks[@]}." >&2
        exit 5
    }
    package_apk="${fetched_apks[0]}"

    "$sdk_dir/staging_dir/host/bin/apk" --allow-untrusted extract \
        --destination "$package_stage/extracted" "$package_apk"

    mapfile -t readelf_candidates < <(
        find "$sdk_dir/staging_dir" -mindepth 3 -maxdepth 4 \( -type f -o -type l \) \
            -path '*/toolchain-*/bin/*-readelf' -print 2>/dev/null | sort -u
    )
    [[ "${#readelf_candidates[@]}" -gt 0 ]] || {
        echo "ERROR: target readelf not found while staging runtime provider $package." >&2
        exit 5
    }
    readelf_bin="${readelf_candidates[0]}"

    mapfile -t libraries < <(
        find "$package_stage/extracted" -type f \( -name '*.so' -o -name '*.so.*' \) -print 2>/dev/null | sort
    )

    mkdir -p "$target_staging/pkginfo"
    runtime_pkg="$(basename "$package_apk" .apk)"
    runtime_pkg="${runtime_pkg%%-[0-9]*}"
    : > "$target_staging/pkginfo/$package.provides"
    : > "$target_staging/pkginfo/$runtime_pkg.provides"

    for library in "${libraries[@]}"; do
        soname="$("$readelf_bin" -d "$library" 2>/dev/null | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p' | head -n1)"
        [[ -n "$soname" ]] || continue
        grep -Fxq "$soname" "$target_staging/pkginfo/$package.provides" ||
            printf '%s\n' "$soname" >> "$target_staging/pkginfo/$package.provides"
        grep -Fxq "$soname" "$target_staging/pkginfo/$runtime_pkg.provides" ||
            printf '%s\n' "$soname" >> "$target_staging/pkginfo/$runtime_pkg.provides"
    done
}

register_official_sdk_source() {
    local feed="$1" source_rel="$2"
    local source_path="$sdk_dir/feeds/$feed/$source_rel"
    local destination="$sdk_dir/package/feeds/$feed/$(basename "$source_rel")"

    [[ -d "$source_path" ]] || {
        echo "ERROR: official OpenWrt source directory is missing: $source_path" >&2
        exit 5
    }
    mkdir -p "$(dirname "$destination")"
    if [[ ! -e "$destination" && ! -L "$destination" ]]; then
        ln -s "$source_path" "$destination"
    fi
}

prepared_source_dir() {
    local source_name="$1" allow_variants="${2:-0}"
    local -a matches=()
    mapfile -t matches < <(
        find "$sdk_dir/build_dir" -mindepth 2 -maxdepth 2 -type d \
            -name "$source_name-*" -print 2>/dev/null | sort
    )
    [[ "${#matches[@]}" -gt 0 ]] || {
        echo "ERROR: no prepared source tree found for $source_name." >&2
        exit 5
    }
    if [[ "$allow_variants" != "1" && "${#matches[@]}" -ne 1 ]]; then
        echo "ERROR: expected one prepared source tree for $source_name, found ${#matches[@]}." >&2
        exit 5
    fi
    # OpenWrt may prepare several build variants from the same source tree
    # (ustream-ssl: mbedTLS/OpenSSL/WolfSSL). Public source headers are common
    # to those variants, so callers that explicitly allow variants may use the
    # first deterministic prepared tree without compiling any variant.
    printf '%s\n' "${matches[0]}"
}

stage_official_link_stub() {
    local package="$1" feed="$2" library_glob="$3" linker_name="$4"
    local target_staging="$5"
    shift 5
    local provider_name="$package"
    if [[ "${1:-}" == "--provider-name" ]]; then
        [[ "$#" -ge 2 ]] || {
            echo "ERROR: --provider-name requires a logical package name for $package." >&2
            exit 5
        }
        provider_name="$2"
        shift 2
    fi
    local package_stage="$work_dir/prebuilt-sdk/$package"
    local package_url package_apk library soname readelf_bin target_cc stub_source runtime_pkg
    local -a libraries=()

    package_url="$(python3 "$repo_root/scripts/resolve-openwrt-package.py" \
        "$release" "$arch_packages" "$feed" "$package")"
    package_apk="$package_stage/$(basename "$package_url")"
    rm -rf "$package_stage"
    mkdir -p "$package_stage/extracted"
    download_file "$package_url" "$package_apk"
    "$sdk_dir/staging_dir/host/bin/apk" --allow-untrusted extract \
        --destination "$package_stage/extracted" "$package_apk"

    mapfile -t libraries < <(find "$package_stage/extracted" -type f -name "$library_glob" -print)
    [[ "${#libraries[@]}" -eq 1 ]] || {
        echo "ERROR: expected one $library_glob in official $package APK, found ${#libraries[@]}." >&2
        exit 5
    }
    library="${libraries[0]}"

    # Only select cross-tools from the target toolchain staging directory.
    # staging_dir/host/bin also contains helpers such as mklibs-readelf; those
    # are host utilities and do not have a matching target compiler.
    local -a target_readelf_candidates=()
    local -a target_cc_candidates=()
    local -A target_tool_pair_seen=()
    local candidate paired_cc canonical_readelf canonical_cc pair_key
    while IFS= read -r candidate; do
        paired_cc="${candidate%readelf}gcc"
        [[ -x "$paired_cc" ]] || continue

        # OpenWrt SDKs may expose multiple target-triplet aliases for the same
        # toolchain (for example mips-openwrt-linux-readelf and
        # mips-openwrt-linux-musl-readelf). Collapse aliases by their resolved
        # readelf/gcc pair instead of treating each pathname as a toolchain.
        canonical_readelf="$(readlink -f "$candidate" 2>/dev/null || true)"
        canonical_cc="$(readlink -f "$paired_cc" 2>/dev/null || true)"
        [[ -x "$canonical_readelf" && -x "$canonical_cc" ]] || continue

        pair_key="$canonical_readelf|$canonical_cc"
        [[ -z "${target_tool_pair_seen[$pair_key]+x}" ]] || continue
        target_tool_pair_seen["$pair_key"]=1
        target_readelf_candidates+=("$canonical_readelf")
        target_cc_candidates+=("$canonical_cc")
    done < <(
        find "$sdk_dir/staging_dir" -mindepth 3 -maxdepth 4 \( -type f -o -type l \) -print 2>/dev/null |
            grep '/toolchain-[^/]*/bin/[^/]*-readelf$' |
            sort -u
    )

    [[ "${#target_readelf_candidates[@]}" -eq 1 ]] || {
        echo "ERROR: expected exactly one distinct target readelf/gcc toolchain pair, found ${#target_readelf_candidates[@]}." >&2
        if [[ "${#target_readelf_candidates[@]}" -gt 0 ]]; then
            printf '  %s\n' "${target_readelf_candidates[@]}" >&2
        fi
        exit 5
    }

    readelf_bin="${target_readelf_candidates[0]}"
    target_cc="${target_cc_candidates[0]}"
    printf 'Official %s runtime library: %s\n' "$package" "$library"
    file "$library" || true
    if ! "$readelf_bin" -h "$library"; then
        echo "ERROR: official $package APK did not extract a valid target ELF library." >&2
        exit 5
    fi

    soname="$("$readelf_bin" -d "$library" 2>/dev/null | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p' | head -n1)"
    [[ -n "$soname" ]] || soname="$(basename "$library")"

    # Runtime APK libraries are aggressively stripped by OpenWrt and have no
    # section headers. They are valid runtime ELFs, but GNU ld cannot consume
    # them as development libraries. Build a tiny target-architecture link stub
    # carrying the exact runtime SONAME. Callers may list the small set of
    # symbols they reference, or request every exported dynamic symbol when a
    # complex upstream package (such as wpa_supplicant) uses a wider API.
    mkdir -p "$target_staging/usr/lib" "$target_staging/pkginfo"
    if [[ "${1:-}" == "--all-dynamic-symbols" ]]; then
        python3 "$repo_root/scripts/create-elf-link-stub.py" \
            "$readelf_bin" "$target_cc" "$library" \
            "$target_staging/usr/lib/$linker_name" "$soname"
    else
        stub_source="$package_stage/link-stub.c"
        : > "$stub_source"
        for symbol in "$@"; do
            [[ "$symbol" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
                echo "ERROR: invalid link-stub symbol for $package: $symbol" >&2
                exit 5
            }

            # uloop exposes two pieces used by inline helpers in uloop.h rather
            # than through ordinary function calls. Keep their symbol kind
            # compatible with the real library.
            case "$symbol" in
                uloop_cancelled)
                    printf 'unsigned char uloop_cancelled;\n' >> "$stub_source"
                    ;;
                uloop_run_timeout)
                    printf 'int uloop_run_timeout(int timeout) { (void)timeout; return 0; }\n' >> "$stub_source"
                    ;;
                *)
                    printf 'void %s(void) {}\n' "$symbol" >> "$stub_source"
                    ;;
            esac
        done

        "$target_cc" -shared -fPIC -Wl,-soname,"$soname" \
            -o "$target_staging/usr/lib/$linker_name" "$stub_source"
    fi

    # Downstream AudioWRT libraries record the real runtime SONAME in DT_NEEDED.
    # Keep an SDK-only alias for that SONAME so GNU ld can resolve transitive
    # dependencies while linking codec players. The alias points to the stub,
    # never to the stripped runtime APK library.
    if [[ "$soname" != "$linker_name" ]]; then
        ln -sf "$linker_name" "$target_staging/usr/lib/$soname"
    fi

    # OpenWrt CheckDependencies expands the package's logical DEPENDS and then
    # concatenates <dependency>.provides. ABI-versioned runtime APKs use a
    # different concrete name (for example libmbedtls21), so keep metadata for
    # both the logical dependency and the concrete runtime package.
    runtime_pkg="$(basename "$package_apk" .apk)"
    runtime_pkg="${runtime_pkg%%-[0-9]*}"
    for provides_file in \
        "$target_staging/pkginfo/$provider_name.provides" \
        "$target_staging/pkginfo/$package.provides" \
        "$target_staging/pkginfo/$runtime_pkg.provides"; do
        touch "$provides_file"
        grep -Fxq "$soname" "$provides_file" || printf '%s\n' "$soname" >> "$provides_file"
    done
}

copy_single_header() {
    local root="$1" name="$2" destination="$3"
    local -a matches=()
    mapfile -t matches < <(find "$root" -type f -name "$name" -print 2>/dev/null | sort)
    [[ "${#matches[@]}" -eq 1 ]] || {
        echo "ERROR: expected one $name under $root, found ${#matches[@]}." >&2
        exit 5
    }
    cp -f "${matches[0]}" "$destination"
}

prepare_native_player_sdk() {
    local -a target_staging_matches=() ustream_headers=()
    local target_staging libubox_src uclient_src ustream_header

    mapfile -t target_staging_matches < <(
        find "$sdk_dir/staging_dir" -mindepth 1 -maxdepth 1 -type d -name 'target-*' -print
    )
    [[ "${#target_staging_matches[@]}" -eq 1 ]] || {
        echo "ERROR: expected one target staging directory, found ${#target_staging_matches[@]}." >&2
        exit 5
    }
    target_staging="${target_staging_matches[0]}"

    make_run "$sdk_dir" \
        package/feeds/base/libubox/prepare \
        package/feeds/base/uclient/prepare \
        package/feeds/base/ustream-ssl/prepare \
        NO_DEPS=1 -j"$jobs"

    libubox_src="$(prepared_source_dir libubox)"
    uclient_src="$(prepared_source_dir uclient)"
    mapfile -t ustream_headers < <(
        find "$sdk_dir/build_dir" -type f -name 'ustream-ssl.h' \
            -path '*/ustream-ssl-*/*' -print 2>/dev/null | sort
    )
    [[ "${#ustream_headers[@]}" -gt 0 ]] || {
        echo "ERROR: no prepared ustream-ssl public header found." >&2
        exit 5
    }
    ustream_header="${ustream_headers[0]}"

    mkdir -p "$target_staging/usr/include/libubox"
    find "$libubox_src" -maxdepth 1 -type f -name '*.h' -exec cp -f {} "$target_staging/usr/include/libubox/" \;
    find "$uclient_src" -maxdepth 1 -type f -name '*.h' -exec cp -f {} "$target_staging/usr/include/libubox/" \;
    cp -f "$ustream_header" "$target_staging/usr/include/libubox/ustream-ssl.h"

    [[ -f "$target_staging/usr/include/libubox/uloop.h" ]] || {
        echo "ERROR: libubox headers were not staged." >&2
        exit 5
    }
    [[ -f "$target_staging/usr/include/libubox/uclient.h" ]] || {
        echo "ERROR: uclient headers were not staged." >&2
        exit 5
    }
    [[ -f "$target_staging/usr/include/libubox/ustream-ssl.h" ]] || {
        echo "ERROR: ustream-ssl headers were not staged." >&2
        exit 5
    }

    stage_official_link_stub libubox base 'libubox.so.*' libubox.so "$target_staging" \
        uloop_cancelled uloop_init uloop_run_timeout uloop_done
    stage_official_link_stub libuclient base 'libuclient.so*' libuclient.so "$target_staging" \
        uclient_disconnect uclient_http_status_redirect uclient_http_redirect \
        uclient_read uclient_new uclient_set_timeout uclient_new_ssl_context \
        uclient_http_set_ssl_ctx uclient_connect uclient_http_set_request_type \
        uclient_http_reset_headers uclient_http_set_header uclient_request uclient_free

    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-flac "* ]]; then
        local flac_src
        make_run "$sdk_dir" package/feeds/packages/flac/prepare NO_DEPS=1 -j"$jobs"
        flac_src="$(prepared_source_dir flac)"
        mkdir -p "$target_staging/usr/include/FLAC"
        cp -f "$flac_src"/include/FLAC/*.h "$target_staging/usr/include/FLAC/"
        [[ -f "$target_staging/usr/include/FLAC/stream_decoder.h" ]] || {
            echo "ERROR: FLAC headers were not staged." >&2
            exit 5
        }
        stage_official_link_stub libflac packages 'libFLAC.so.*' libFLAC.so "$target_staging" \
            FLAC__stream_decoder_new FLAC__stream_decoder_init_FILE \
            FLAC__stream_decoder_process_until_end_of_stream \
            FLAC__stream_decoder_finish FLAC__stream_decoder_delete
    fi

    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-mp3 "* ]]; then
        local mad_src
        # libmad 0.16.4 generates mad.h from its CMake configuration. Prepare
        # alone leaves only the source inputs, while configure creates the public
        # header without compiling or replacing the official runtime library.
        make_run "$sdk_dir" package/feeds/packages/libmad/configure NO_DEPS=1 -j"$jobs"
        mad_src="$(prepared_source_dir libmad)"
        mkdir -p "$target_staging/usr/include"
        copy_single_header "$mad_src" mad.h "$target_staging/usr/include/mad.h"
        stage_official_link_stub libmad packages 'libmad.so.*' libmad.so "$target_staging" \
            mad_decoder_init mad_decoder_run mad_decoder_finish mad_stream_buffer
    fi

    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-aac "* ]]; then
        local faad_src
        make_run "$sdk_dir" package/feeds/packages/faad2/prepare NO_DEPS=1 -j"$jobs"
        faad_src="$(prepared_source_dir faad2)"
        mkdir -p "$target_staging/usr/include"
        copy_single_header "$faad_src" neaacdec.h "$target_staging/usr/include/neaacdec.h"
        stage_official_link_stub libfaad2 packages 'libfaad.so.*' libfaad.so "$target_staging" \
            NeAACDecOpen NeAACDecGetCurrentConfiguration NeAACDecSetConfiguration \
            NeAACDecInit NeAACDecDecode NeAACDecClose
    fi

    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-vorbis "* ||
          " ${firmware_packages[*]} " == *" audiowrt-player-opus "* ]]; then
        local ogg_src ogg_config
        # libogg generates config_types.h during configure; prepare alone leaves
        # os_types.h including a header that does not exist yet.
        make_run "$sdk_dir" package/feeds/packages/libogg/configure NO_DEPS=1 -j"$jobs"
        ogg_src="$(prepared_source_dir libogg)"
        mkdir -p "$target_staging/usr/include/ogg"
        cp -f "$ogg_src"/include/ogg/*.h "$target_staging/usr/include/ogg/"
        mapfile -t ogg_configs < <(find "$ogg_src" -type f -path '*/ogg/config_types.h' -print 2>/dev/null | sort)
        [[ "${#ogg_configs[@]}" -eq 1 ]] || {
            echo "ERROR: expected generated Ogg config_types.h, found ${#ogg_configs[@]}." >&2
            exit 5
        }
        cp -f "${ogg_configs[0]}" "$target_staging/usr/include/ogg/config_types.h"
    fi

    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-vorbis "* ]]; then
        local vorbis_src
        make_run "$sdk_dir" package/feeds/packages/libvorbis/prepare NO_DEPS=1 -j"$jobs"
        vorbis_src="$(prepared_source_dir libvorbis)"
        mkdir -p "$target_staging/usr/include/vorbis"
        cp -f "$vorbis_src"/include/vorbis/*.h "$target_staging/usr/include/vorbis/"
        [[ -f "$target_staging/usr/include/vorbis/vorbisfile.h" ]] || {
            echo "ERROR: Vorbis headers were not staged." >&2
            exit 5
        }
        stage_official_link_stub libvorbis packages 'libvorbisfile.so.*' libvorbisfile.so "$target_staging" \
            ov_open_callbacks ov_read ov_info ov_clear
    fi

    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-opus "* ]]; then
        local opus_src opusfile_src
        make_run "$sdk_dir" package/feeds/packages/opus/prepare NO_DEPS=1 -j"$jobs"
        make_run "$sdk_dir" package/feeds/packages/opusfile/prepare NO_DEPS=1 -j"$jobs"
        opus_src="$(prepared_source_dir opus)"
        opusfile_src="$(prepared_source_dir opusfile)"
        mkdir -p "$target_staging/usr/include/opus"
        find "$opus_src/include" -maxdepth 1 -type f -name '*.h' -exec cp -f {} "$target_staging/usr/include/opus/" \;
        find "$opusfile_src/include" -maxdepth 1 -type f -name '*.h' -exec cp -f {} "$target_staging/usr/include/opus/" \;
        [[ -f "$target_staging/usr/include/opus/opusfile.h" ]] || {
            echo "ERROR: opusfile headers were not staged." >&2
            exit 5
        }
        stage_official_link_stub libopusfile packages 'libopusfile.so.*' libopusfile.so "$target_staging" \
            op_open_callbacks op_read_stereo op_free
    fi
}

prepare_hostap_sdk() {
    local -a target_staging_matches=()
    local target_staging libubox_src ubus_src ucode_src udebug_src mbedtls_src

    mapfile -t target_staging_matches < <(
        find "$sdk_dir/staging_dir" -mindepth 1 -maxdepth 1 -type d -name 'target-*' -print
    )
    [[ "${#target_staging_matches[@]}" -eq 1 ]] || {
        echo "ERROR: expected one target staging directory, found ${#target_staging_matches[@]}." >&2
        exit 5
    }
    target_staging="${target_staging_matches[0]}"

    # AudioWRT's multicall wpad needs these development interfaces, but the
    # firmware must keep
    # the exact official OpenWrt runtime packages. Compile only libnl-tiny
    # and libjson-c with NO_DEPS=1: libjson-c supplies the public headers pulled
    # in by libucode's headers, while the final image still resolves the official
    # libjson-c runtime transitively through libucode. Prepare the remaining
    # source trees for headers and link against build-only stubs generated from
    # the official release APKs instead of rebuilding ubus/ucode/udebug.
    make_run "$sdk_dir" \
        package/feeds/base/libnl-tiny/compile \
        package/feeds/base/libjson-c/compile \
        package/feeds/base/mbedtls/configure \
        package/feeds/base/libubox/prepare \
        package/feeds/base/ubus/prepare \
        package/feeds/base/ucode/prepare \
        package/feeds/base/udebug/prepare \
        NO_DEPS=1 -j"$jobs"

    libubox_src="$(prepared_source_dir libubox)"
    ubus_src="$(prepared_source_dir ubus)"
    ucode_src="$(prepared_source_dir ucode)"
    udebug_src="$(prepared_source_dir udebug)"
    mbedtls_src="$(prepared_source_dir mbedtls)"

    mkdir -p \
        "$target_staging/usr/include/libubox" \
        "$target_staging/usr/include/ucode" \
        "$target_staging/usr/include/mbedtls" \
        "$target_staging/usr/include/psa" \
        "$target_staging/usr/include"

    find "$libubox_src" -maxdepth 1 -type f -name '*.h' \
        -exec cp -f {} "$target_staging/usr/include/libubox/" \;
    find "$ubus_src" -maxdepth 1 -type f -name '*.h' \
        -exec cp -f {} "$target_staging/usr/include/" \;
    cp -f "$ucode_src"/include/ucode/*.h "$target_staging/usr/include/ucode/"
    find "$udebug_src" -maxdepth 1 -type f -name '*.h' \
        -exec cp -f {} "$target_staging/usr/include/" \;
    cp -f "$mbedtls_src"/include/mbedtls/*.h "$target_staging/usr/include/mbedtls/"
    cp -f "$mbedtls_src"/include/psa/*.h "$target_staging/usr/include/psa/"

    for header in \
        libubox/uloop.h \
        libubox/blobmsg_json.h \
        libubus.h \
        json-c/json.h \
        ucode/lib.h \
        udebug.h \
        mbedtls/ssl.h \
        mbedtls/mbedtls_config.h \
        psa/crypto.h; do
        [[ -f "$target_staging/usr/include/$header" ]] || {
            echo "ERROR: WPA SDK header was not staged: $header" >&2
            exit 5
        }
    done

    stage_official_link_stub libubox base 'libubox.so.*' libubox.so \
        "$target_staging" --all-dynamic-symbols
    stage_official_link_stub libblobmsg-json base 'libblobmsg_json.so.*' \
        libblobmsg_json.so "$target_staging" --all-dynamic-symbols
    stage_official_link_stub libubus base 'libubus.so.*' libubus.so \
        "$target_staging" --all-dynamic-symbols
    stage_official_link_stub libucode base 'libucode.so.*' libucode.so \
        "$target_staging" --all-dynamic-symbols
    stage_official_link_stub libudebug base 'libudebug.so*' libudebug.so \
        "$target_staging" --all-dynamic-symbols
    stage_official_link_stub libmbedtls21 base 'libmbedcrypto.so.*' libmbedcrypto.so \
        "$target_staging" --provider-name libmbedtls --all-dynamic-symbols
    stage_official_link_stub libmbedtls21 base 'libmbedx509.so.*' libmbedx509.so \
        "$target_staging" --provider-name libmbedtls --all-dynamic-symbols
    stage_official_link_stub libmbedtls21 base 'libmbedtls.so.*' libmbedtls.so \
        "$target_staging" --provider-name libmbedtls --all-dynamic-symbols
}

