include $(TOPDIR)/rules.mk

PKG_NAME:=libaudiowrt-player
PKG_VERSION:=1.1.2
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/libaudiowrt-player
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=AudioWRT native player transport and PCM library
  DEPENDS:=+libuclient +libubox +alsa-lib +uci
endef

define Package/libaudiowrt-player/description
 Shared native AudioWRT player library. Streams HTTP/HTTPS with libuclient and
 writes PCM directly through ALSA without invoking wget, uclient-fetch or curl.\n It also owns the idempotent playback registry used by player packages. Codec
 capabilities and player implementations are stored in separate UCI packages.
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


define Package/libaudiowrt-player/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/libaudiowrt-player.so.0 $(1)/usr/lib/libaudiowrt-player.so.0
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/audiowrt-playback-registry $(1)/usr/libexec/audiowrt-playback-registry
	$(INSTALL_DIR) $(1)/etc/config
	ln -s /tmp/audiowrt/registry/audiowrt-codecs $(1)/etc/config/audiowrt-runtime-codecs
	ln -s /tmp/audiowrt/registry/audiowrt-players $(1)/etc/config/audiowrt-runtime-players
	$(INSTALL_DIR) $(1)/etc/init.d $(1)/etc/rc.d
	$(INSTALL_BIN) ./files/playback-registry.init $(1)/etc/init.d/audiowrt-playback-registry
	ln -s ../init.d/audiowrt-playback-registry $(1)/etc/rc.d/S12audiowrt-playback-registry
endef
define Package/libaudiowrt-player/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-playback-registry rebuild
exit 0
endef

$(eval $(call BuildPackage,libaudiowrt-player))
