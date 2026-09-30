include $(TOPDIR)/rules.mk

AUDIOWRT_DERIVED_NAME:=audiowrt-sbc
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/packages/libs/sbc/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk

PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-sbc
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=AudioWRT minimal SBC encoding library
  URL:=https://www.bluez.org/
endef

define Package/audiowrt-sbc/description
 Library-only SBC codec derived from the selected OpenWrt packages feed for
 AudioWRT Bluetooth A2DP. Command-line tools and the tester dependency chain
 are intentionally omitted.
endef

CONFIGURE_ARGS += \
	--disable-static \
	--disable-tester

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include/sbc
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/usr/include/sbc/sbc.h $(1)/usr/include/sbc/
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libsbc* $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/lib/pkgconfig
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/sbc.pc $(1)/usr/lib/pkgconfig/
endef

define Package/audiowrt-sbc/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libsbc.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,audiowrt-sbc))
