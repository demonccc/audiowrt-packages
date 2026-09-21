include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-aiff
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-aiff
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native AIFF player
  DEPENDS:=+libaudiowrt-player +libpthread
endef

define Package/audiowrt-player-aiff/description
 Native AudioWRT AIFF PCM player using the shared HTTP/HTTPS transport and
 ALSA framework. Supports uncompressed 8/16/24/32-bit AIFF streams.
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
		-o $(PKG_BUILD_DIR)/audiowrt-player-aiff \
		$(PKG_BUILD_DIR)/audiowrt-player-aiff.c \
		$(TARGET_LDFLAGS) -Wl,-rpath-link,$(STAGING_DIR)/usr/lib -laudiowrt-player -lpthread -lm
endef

define Package/audiowrt-player-aiff/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-aiff $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/aiff.defaults $(1)/etc/uci-defaults/70-audiowrt-player-aiff
endef

define Package/audiowrt-player-aiff/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-player-registry register aiff native_aiff 'AudioWRT AIFF Player' /usr/bin/audiowrt-player-aiff 'audio/aiff audio/x-aiff' 'aif aiff' >/dev/null 2>&1 || true
exit 0
endef

define Package/audiowrt-player-aiff/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-player-registry unregister native_aiff >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,audiowrt-player-aiff))
