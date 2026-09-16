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
AUDIOWRT_DERIVED_STAMP:=$(AUDIOWRT_DERIVED_WORK)/prepared

# Official SDKs expose the OpenWrt core package tree as the pinned `base` feed.
# AudioWRT distribution builds normally update it before package parsing, but a
# derived package must also be usable when its feed is built directly. Resolve
# that exact SDK-pinned feed lazily when a base recipe has not been materialized
# yet. No branch name or AudioWRT-owned OpenWrt revision is substituted here.
ifneq ($(findstring $(TOPDIR)/feeds/base/,$(AUDIOWRT_CANONICAL_RECIPE)),)
ifeq ($(wildcard $(AUDIOWRT_CANONICAL_RECIPE)),)
  $(info AudioWRT: resolving exact OpenWrt base feed for $(AUDIOWRT_DERIVED_NAME))
  $(shell cd '$(TOPDIR)' && ./scripts/feeds update base >/dev/null 2>&1)
endif
endif

# VERSION_NUMBER is supplied by the selected OpenWrt SDK. The helper copies the
# canonical release-specific files/patches and emits the canonical recipe
# preamble before package.mk is included by the AudioWRT recipe body.
$(shell \
	mkdir -p '$(AUDIOWRT_DERIVED_WORK)' && \
	rm -f '$(AUDIOWRT_DERIVED_STAMP)' && \
	python3 '$(TOPDIR)/feeds/audiowrt/scripts/prepare-openwrt-derived.py' \
		'$(AUDIOWRT_CANONICAL_RECIPE)' \
		'$(AUDIOWRT_DERIVED_ROOT)' \
		'$(VERSION_NUMBER)' \
		'$(AUDIOWRT_DERIVED_PREAMBLE)' \
		'$(AUDIOWRT_DERIVED_RELEASE_RECIPE)' \
		'$(AUDIOWRT_DERIVED_PATCH_DIR)' \
		'$(AUDIOWRT_DERIVED_FILES_DIR)' \
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
