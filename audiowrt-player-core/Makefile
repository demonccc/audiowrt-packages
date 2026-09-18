include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-core
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-core
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native player transport and PCM core
  DEPENDS:=+libuclient +libubox +alsa-lib
endef

define Package/audiowrt-player-core/description
 Shared native AudioWRT player runtime. Streams HTTP/HTTPS with libuclient and
 writes PCM directly through ALSA without invoking wget, uclient-fetch or curl.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) -fPIC -shared \
		-Wl,-soname,libaudiowrt-player.so.0 \
		-o $(PKG_BUILD_DIR)/libaudiowrt-player.so.0 \
		$(PKG_BUILD_DIR)/audiowrt-player.c \
		$(TARGET_LDFLAGS) -luclient -lubox -lasound
	ln -sf libaudiowrt-player.so.0 $(PKG_BUILD_DIR)/libaudiowrt-player.so
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include/audiowrt
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/audiowrt-player.h $(1)/usr/include/audiowrt/player.h
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/libaudiowrt-player.so* $(1)/usr/lib/
endef

define Package/audiowrt-player-core/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/libaudiowrt-player.so.0 $(1)/usr/lib/libaudiowrt-player.so.0
endef

$(eval $(call BuildPackage,audiowrt-player-core))
