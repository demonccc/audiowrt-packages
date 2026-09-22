include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-flac
PKG_VERSION:=1.0.2
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-flac
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native FLAC player
  DEPENDS:=+libaudiowrt-player +libflac +libpthread
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) \
		-I$(STAGING_DIR)/usr/include/audiowrt \
		-o $(PKG_BUILD_DIR)/audiowrt-player-flac \
		$(PKG_BUILD_DIR)/audiowrt-player-flac.c \
		$(TARGET_LDFLAGS) -Wl,-rpath-link,$(STAGING_DIR)/usr/lib -laudiowrt-player -lFLAC -lpthread
endef

define Package/audiowrt-player-flac/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-flac $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/flac.defaults $(1)/etc/uci-defaults/70-audiowrt-player-flac
endef

define Package/audiowrt-player-flac/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-playback-registry register flac native_flac 'AudioWRT FLAC Player' /usr/bin/audiowrt-player-flac 'audio/flac audio/x-flac' 'flac' >/dev/null 2>&1 || true
exit 0
endef

define Package/audiowrt-player-flac/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-playback-registry unregister native_flac >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,audiowrt-player-flac))
