# SPDX-License-Identifier: Apache-2.0

# Keep LuCI JavaScript readable in the AudioWRT source tree, but minify the
# package payload with the same jsmin implementation shipped by LuCI.
AUDIOWRT_JSMIN_SOURCE:=$(TOPDIR)/feeds/luci/modules/luci-base/src/jsmin.c
AUDIOWRT_JSMIN:=$(PKG_BUILD_DIR)/audiowrt-jsmin

define AudioWRT/BuildJsMin
	[ -f "$(AUDIOWRT_JSMIN_SOURCE)" ] || { \
		echo "ERROR: LuCI jsmin source is unavailable: $(AUDIOWRT_JSMIN_SOURCE)" >&2; \
		exit 1; \
	}
	mkdir -p "$(PKG_BUILD_DIR)"
	$(HOSTCC) -O2 -o "$(AUDIOWRT_JSMIN)" "$(AUDIOWRT_JSMIN_SOURCE)"
endef

define AudioWRT/MinifyJS
	find "$(1)" -type f -name '*.js' -exec sh -c ' \
		for src do \
			tmp="$$src.min"; \
			"$(AUDIOWRT_JSMIN)" < "$$src" > "$$tmp" || exit $$?; \
			mv -f "$$tmp" "$$src" || exit $$?; \
		done \
	' sh {} +
endef
