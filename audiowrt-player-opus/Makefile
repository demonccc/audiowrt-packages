include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-opus
PKG_VERSION:=1.0.2
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-opus
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native Ogg Opus player
  DEPENDS:=+libaudiowrt-player +libopusfile +libpthread
endef

define Package/audiowrt-player-opus/description
 Native AudioWRT Ogg Opus player using libopusfile with the shared
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
		-o $(PKG_BUILD_DIR)/audiowrt-player-opus \
		$(PKG_BUILD_DIR)/audiowrt-player-opus.c \
		$(TARGET_LDFLAGS) -Wl,-rpath-link,$(STAGING_DIR)/usr/lib -laudiowrt-player -lopusfile -lpthread
endef

define Package/audiowrt-player-opus/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-opus $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/opus.defaults $(1)/etc/uci-defaults/70-audiowrt-player-opus
endef

define Package/audiowrt-player-opus/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-playback-registry register opus native_opus 'AudioWRT Opus Player' /usr/bin/audiowrt-player-opus 'audio/opus audio/ogg;codecs=opus audio/ogg application/ogg' 'opus ogg oga' >/dev/null 2>&1 || true
exit 0
endef

define Package/audiowrt-player-opus/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-playback-registry unregister native_opus >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,audiowrt-player-opus))
