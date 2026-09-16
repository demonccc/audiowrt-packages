# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

AUDIOWRT_DERIVED_NAME:=audiowrt-umdns
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/package/network/services/umdns/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk

PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/audiowrt-umdns
  SECTION:=net
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT minimal mDNS daemon
  DEPENDS:=+libubox +libubus +libblobmsg-json +libudebug
  PROVIDES:=umdns
  CONFLICTS:=umdns
endef

define Package/audiowrt-umdns/description
 Minimal umdns derived from the selected OpenWrt release. It keeps the daemon
 and UCI/procd integration needed for .local naming and mDNS publication while
 omitting the CLI ucode helper and seccomp payload from constrained images.
endef

define Package/audiowrt-umdns/conffiles
/etc/config/umdns
endef

TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include

define Package/audiowrt-umdns/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/umdns $(1)/usr/sbin/umdns
	$(INSTALL_BIN) $(AUDIOWRT_DERIVED_FILES_DIR)/umdns.init $(1)/etc/init.d/umdns
	$(INSTALL_CONF) $(AUDIOWRT_DERIVED_FILES_DIR)/umdns.config $(1)/etc/config/umdns
endef

$(eval $(call BuildPackage,audiowrt-umdns))
