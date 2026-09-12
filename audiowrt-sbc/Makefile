include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-sbc
PKG_VERSION:=2.0
PKG_RELEASE:=2

PKG_SOURCE:=sbc-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=@KERNEL/linux/bluetooth/
PKG_HASH:=8f12368e1dbbf55e14536520473cfb338c84b392939cc9b64298360fd4a07992
PKG_BUILD_DIR:=$(BUILD_DIR)/sbc-$(PKG_VERSION)

PKG_LICENSE:=LGPL-2.1-or-later
PKG_LICENSE_FILES:=COPYING.LIB
PKG_MAINTAINER:=AudioWRT
PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=lto

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-sbc
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=AudioWRT minimal SBC encoding library
  URL:=https://www.bluez.org/
endef

define Package/audiowrt-sbc/description
 Library-only SBC codec package for AudioWRT Bluetooth A2DP. Unlike the
 generic OpenWrt sbc package, it does not install command-line tools and does
 not pull libsndfile or its MP3/audio-format dependency chain into firmware.
endef

# libsndfile is only required by the upstream SBC tester. AudioWRT needs the
# codec library for BlueALSA, so disable the tester and keep the runtime free of
# libsndfile/lame/mpg123.
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
