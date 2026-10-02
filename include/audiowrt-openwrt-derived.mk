# SPDX-License-Identifier: GPL-2.0-only
#
# Common helper for AudioWRT packages derived from a canonical OpenWrt package.
# The package Makefile must set:
#   AUDIOWRT_DERIVED_NAME
#   AUDIOWRT_CANONICAL_RECIPE
# before including this file.

ifndef AUDIOWRT_DERIVED_NAME
  $(error AUDIOWRT_DERIVED_NAME is required)
endif
ifndef AUDIOWRT_CANONICAL_RECIPE
  $(error AUDIOWRT_CANONICAL_RECIPE is required)
endif

# AudioWRT is a regular recursive OpenWrt feed. Packages are grouped by
# ownership/type in audiowrt/, ported/, trimmed/ and tailored/. Keep a flat-path
# fallback for older checkouts while resolving the real nested package root.
AUDIOWRT_DERIVED_ROOT:=$(firstword $(wildcard \
  $(TOPDIR)/feeds/audiowrt/$(AUDIOWRT_DERIVED_NAME) \
  $(TOPDIR)/feeds/audiowrt/audiowrt/$(AUDIOWRT_DERIVED_NAME) \
  $(TOPDIR)/feeds/audiowrt/ported/$(AUDIOWRT_DERIVED_NAME) \
  $(TOPDIR)/feeds/audiowrt/trimmed/$(AUDIOWRT_DERIVED_NAME) \
  $(TOPDIR)/feeds/audiowrt/tailored/$(AUDIOWRT_DERIVED_NAME)))
ifeq ($(AUDIOWRT_DERIVED_ROOT),)
  $(error AudioWRT derived package root is missing for $(AUDIOWRT_DERIVED_NAME))
endif

AUDIOWRT_DERIVED_WORK:=$(TMP_DIR)/audiowrt-derived/$(AUDIOWRT_DERIVED_NAME)
AUDIOWRT_DERIVED_PREAMBLE:=$(AUDIOWRT_DERIVED_WORK)/upstream-preamble.mk
AUDIOWRT_DERIVED_RELEASE_RECIPE:=$(AUDIOWRT_DERIVED_WORK)/release-recipe.mk
AUDIOWRT_DERIVED_PATCH_DIR:=$(AUDIOWRT_DERIVED_WORK)/patches
AUDIOWRT_DERIVED_FILES_DIR:=$(AUDIOWRT_DERIVED_WORK)/files
AUDIOWRT_DERIVED_SRC_DIR:=$(AUDIOWRT_DERIVED_WORK)/src
AUDIOWRT_DERIVED_STAMP:=$(AUDIOWRT_DERIVED_WORK)/prepared

# The exact-release AudioWRT builder indexes the AudioWRT feed before it
# selectively registers OpenWrt core package sources for SDK preparation. Some
# SDKs already carry the canonical recipe under package/, so the old fallback
# path never materialized feeds/base even though the later builder stage expects
# those exact pinned sources there. Materialize the SDK-pinned base checkout
# during AudioWRT's containerized feed scan without indexing or installing it.
ifneq ($(AUDIOWRT_IN_CONTAINER),)
ifneq ($(findstring $(TOPDIR)/feeds/base/,$(AUDIOWRT_CANONICAL_RECIPE)),)
  $(shell python3 '$(TOPDIR)/feeds/audiowrt/scripts/materialize-openwrt-base.py' '$(TOPDIR)')
endif
endif

# Core recipes can already be present in a full OpenWrt checkout or in some SDK
# layouts under $(TOPDIR)/package. Prefer that tree when available.
AUDIOWRT_CANONICAL_RECIPE_RESOLVED:=$(AUDIOWRT_CANONICAL_RECIPE)
ifneq ($(findstring $(TOPDIR)/feeds/base/,$(AUDIOWRT_CANONICAL_RECIPE)),)
  AUDIOWRT_CORE_RECIPE:=$(patsubst $(TOPDIR)/feeds/base/%,$(TOPDIR)/package/%,$(AUDIOWRT_CANONICAL_RECIPE))
  ifneq ($(wildcard $(AUDIOWRT_CORE_RECIPE)),)
    AUDIOWRT_CANONICAL_RECIPE_RESOLVED:=$(AUDIOWRT_CORE_RECIPE)
  else
    # Official SDKs do not necessarily ship the full core package source tree.
    # Materialize only the exact SDK-pinned base source checkout so derived
    # packages can read canonical recipes and patches while the AudioWRT feed is
    # being indexed. This deliberately does NOT run `scripts/feeds update base`:
    # no base feed index is generated and no package is installed or compiled.
    $(shell python3 '$(TOPDIR)/feeds/audiowrt/scripts/materialize-openwrt-base.py' '$(TOPDIR)')
    ifneq ($(wildcard $(AUDIOWRT_CANONICAL_RECIPE)),)
      AUDIOWRT_CANONICAL_RECIPE_RESOLVED:=$(AUDIOWRT_CANONICAL_RECIPE)
    endif
  endif
endif

# Derived recipes resolve only against source trees already present in the
# selected OpenWrt context or the exact base source checkout materialized from
# that context's feeds.conf. External feed recipes live under their exact feed
# checkout (for example $(TOPDIR)/feeds/packages).
#
# Never run feeds update/install from a package Makefile. Feed indexing invokes
# package Makefiles with DUMP=1; recursively indexing another feed from here can
# duplicate Kconfig symbols and destroy the selective-build boundary.
ifeq ($(wildcard $(AUDIOWRT_CANONICAL_RECIPE_RESOLVED)),)
  $(error Canonical OpenWrt recipe is not present in selected build context: $(AUDIOWRT_CANONICAL_RECIPE_RESOLVED))
endif

# During a normal package build VERSION_NUMBER has already been populated by
# OpenWrt. During `scripts/feeds update`, package Makefiles can be dumped before
# include/version.mk is loaded, so the helper also receives TOPDIR and resolves
# the version from that selected source tree/SDK when necessary.
#
# Context-specific AudioWRT patches are selected from ARCH_PACKAGES and
# BOARD/SUBTARGET. Empty values during feed indexing are valid; the normal build
# evaluation prepares the package again with the concrete build context.
$(shell \
	mkdir -p '$(AUDIOWRT_DERIVED_WORK)' && \
	rm -f '$(AUDIOWRT_DERIVED_STAMP)' && \
	python3 '$(TOPDIR)/feeds/audiowrt/scripts/prepare-openwrt-derived.py' \
		'$(AUDIOWRT_CANONICAL_RECIPE_RESOLVED)' \
		'$(AUDIOWRT_DERIVED_ROOT)' \
		'$(VERSION_NUMBER)' \
		'$(TOPDIR)' \
		'$(ARCH_PACKAGES)' \
		'$(BOARD)' \
		'$(SUBTARGET)' \
		'$(AUDIOWRT_DERIVED_PREAMBLE)' \
		'$(AUDIOWRT_DERIVED_RELEASE_RECIPE)' \
		'$(AUDIOWRT_DERIVED_PATCH_DIR)' \
		'$(AUDIOWRT_DERIVED_FILES_DIR)' \
		'$(AUDIOWRT_DERIVED_SRC_DIR)' \
		'$(AUDIOWRT_DERIVED_STAMP)')

ifeq ($(wildcard $(AUDIOWRT_DERIVED_STAMP)),)
  $(error Failed to prepare exact-release OpenWrt package metadata for $(AUDIOWRT_DERIVED_NAME))
endif

include $(AUDIOWRT_DERIVED_PREAMBLE)
-include $(AUDIOWRT_DERIVED_RELEASE_RECIPE)

# Build/Prepare/Default applies PATCH_DIR, so the source tree receives the full
# patch set from the exact selected OpenWrt release plus only explicit 9xx
# AudioWRT patches.
PATCH_DIR:=$(AUDIOWRT_DERIVED_PATCH_DIR)

# OpenWrt's default Build/Prepare copies a package-local ./src overlay into the
# unpacked source tree before applying patches. Derived packages keep the
# canonical overlay in AUDIOWRT_DERIVED_SRC_DIR instead, so recipes that need
# it can opt into this equivalent prepare sequence.
define Build/Prepare/AudioWRTDerived
	$(PKG_UNPACK)
	-find $(PKG_BUILD_DIR) -mindepth 1 -type f -not -name '.*' -not -name 'version.date' -printf '%T@\n' 2>/dev/null |\
		cut -d. -f1 | sort -n | tail -n1 > $(PKG_BUILD_DIR)/version.date
	[ ! -d "$(AUDIOWRT_DERIVED_SRC_DIR)" ] || $(CP) "$(AUDIOWRT_DERIVED_SRC_DIR)/." "$(PKG_BUILD_DIR)"
	$(Build/Patch)
endef
