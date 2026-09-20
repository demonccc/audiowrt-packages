include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-vorbis
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-vorbis
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native Ogg Vorbis player
  DEPENDS:=+libaudiowrt-player +libvorbis +libpthread
endef

define Package/audiowrt-player-vorbis/description
 Native AudioWRT Ogg Vorbis player using libvorbisfile and the shared
 AudioWRT HTTP/HTTPS transport and ALSA framework.
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
		-o $(PKG_BUILD_DIR)/audiowrt-player-vorbis \
		$(PKG_BUILD_DIR)/audiowrt-player-vorbis.c \
		$(TARGET_LDFLAGS) -Wl,-rpath-link,$(STAGING_DIR)/usr/lib \
		-laudiowrt-player -lvorbisfile -lvorbis -logg -lpthread
endef

define Package/audiowrt-player-vorbis/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-vorbis $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/vorbis.defaults $(1)/etc/uci-defaults/70-audiowrt-player-vorbis
endef

define Package/audiowrt-player-vorbis/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-player-registry register vorbis native_vorbis 'AudioWRT Ogg Vorbis Player' /usr/bin/audiowrt-player-vorbis 'audio/ogg audio/vorbis audio/vorbis+ogg application/ogg' 'ogg oga' >/dev/null 2>&1 || true
exit 0
endef

define Package/audiowrt-player-vorbis/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-player-registry unregister native_vorbis >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,audiowrt-player-vorbis))
