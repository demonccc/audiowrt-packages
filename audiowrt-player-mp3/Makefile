include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-mp3
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-mp3
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native MP3 player
  DEPENDS:=+libaudiowrt-player +libmad +libpthread
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
		-o $(PKG_BUILD_DIR)/audiowrt-player-mp3 \
		$(PKG_BUILD_DIR)/audiowrt-player-mp3.c \
		$(TARGET_LDFLAGS) -Wl,-rpath-link,$(STAGING_DIR)/usr/lib -laudiowrt-player -lmad -lpthread
endef

define Package/audiowrt-player-mp3/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-mp3 $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/mp3.defaults $(1)/etc/uci-defaults/70-audiowrt-player-mp3
endef

define Package/audiowrt-player-mp3/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-player-registry register mp3 native_mp3 'AudioWRT MP3 Player' /usr/bin/audiowrt-player-mp3 'audio/mpeg audio/mp3' 'mp3' >/dev/null 2>&1 || true
exit 0
endef

define Package/audiowrt-player-mp3/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-player-registry unregister native_mp3 >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,audiowrt-player-mp3))
