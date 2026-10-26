include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-mpd
PKG_VERSION:=1.2.0
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-mpd
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT MPD player adapter
  DEPENDS:=+libaudiowrt-player +uci
  EXTRA_DEPENDS:=mpd (>=0)
endef

define Package/audiowrt-player-mpd/description
 Integrates the existing OpenWrt MPD instance into the AudioWRT playback
 registry without replacing MPD configuration or changing its ALSA output.
 The installer reuses an existing local/any MPD listener when possible and
 adds a dedicated localhost listener only when explicit MPD bindings otherwise
 make local control impossible. Codec capabilities are detected from MPD at
 installation time and can be refreshed manually later.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) -D_GNU_SOURCE \
		-o $(PKG_BUILD_DIR)/audiowrt-player-mpd \
		$(PKG_BUILD_DIR)/audiowrt-player-mpd.c \
		$(TARGET_LDFLAGS)
endef

define Package/audiowrt-player-mpd/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-mpd $(1)/usr/bin/
	$(INSTALL_BIN) ./files/mpd-refresh-codecs $(1)/usr/bin/audiowrt-mpd-refresh-codecs

	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt
	$(INSTALL_BIN) ./files/mpd-configure $(1)/usr/libexec/audiowrt/mpd-configure

	$(INSTALL_DIR) $(1)/usr/share/audiowrt/players
	$(INSTALL_DATA) ./files/mpd.manifest $(1)/usr/share/audiowrt/players/mpd.manifest

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt_mpd.config $(1)/etc/config/audiowrt_mpd

	# Optional LuCI integration. These files are inert on systems without LuCI.
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/audiowrt
	$(INSTALL_DATA) ./files/luci/mpd.js $(1)/www/luci-static/resources/view/audiowrt/mpd.js
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./files/luci/menu.json $(1)/usr/share/luci/menu.d/audiowrt-player-mpd.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/luci/acl.json $(1)/usr/share/rpcd/acl.d/audiowrt-player-mpd.json
endef

define Package/audiowrt-player-mpd/conffiles
/etc/config/audiowrt_mpd
endef

define Package/audiowrt-player-mpd/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt/mpd-configure || true
/usr/bin/audiowrt-mpd-refresh-codecs refresh || /usr/libexec/audiowrt-playback-registry rebuild
exit 0
endef

define Package/audiowrt-player-mpd/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-playback-registry exclude mpd
rm -f /etc/audiowrt/mpd-codecs.conf /etc/audiowrt/mpd-decoders.txt
exit 0
endef

$(eval $(call BuildPackage,audiowrt-player-mpd))
