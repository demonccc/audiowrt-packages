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

AUDIOWRT_DERIVED_ROOT:=$(TOPDIR)/feeds/audiowrt/$(AUDIOWRT_DERIVED_NAME)
AUDIOWRT_DERIVED_WORK:=$(TMP_DIR)/audiowrt-derived/$(AUDIOWRT_DERIVED_NAME)
AUDIOWRT_DERIVED_PREAMBLE:=$(AUDIOWRT_DERIVED_WORK)/upstream-preamble.mk
AUDIOWRT_DERIVED_RELEASE_RECIPE:=$(AUDIOWRT_DERIVED_WORK)/release-recipe.mk
AUDIOWRT_DERIVED_PATCH_DIR:=$(AUDIOWRT_DERIVED_WORK)/patches
AUDIOWRT_DERIVED_FILES_DIR:=$(AUDIOWRT_DERIVED_WORK)/files
AUDIOWRT_DERIVED_SRC_DIR:=$(AUDIOWRT_DERIVED_WORK)/src
AUDIOWRT_DERIVED_STAMP:=$(AUDIOWRT_DERIVED_WORK)/prepared

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
# prepare-openwrt-derived.py emits only the canonical pre-package.mk preamble
# (source identity/build flags), canonical patches/files/source overlays and
# AudioWRT deltas. It never imports upstream Package/* definitions, DEPENDS or
# BuildPackage calls.
$(shell \
	mkdir -p '$(AUDIOWRT_DERIVED_WORK)' && \
	rm -f '$(AUDIOWRT_DERIVED_STAMP)' && \
	python3 '$(TOPDIR)/feeds/audiowrt/scripts/prepare-openwrt-derived.py' \
		'$(AUDIOWRT_CANONICAL_RECIPE_RESOLVED)' \
		'$(AUDIOWRT_DERIVED_ROOT)' \
		'$(VERSION_NUMBER)' \
		'$(TOPDIR)' \
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
