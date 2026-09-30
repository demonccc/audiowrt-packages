include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-mpd
PKG_VERSION:=1.2.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-mpd
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT MPD player adapter
  DEPENDS:=+mpd +libmpdclient +libuci +libaudiowrt-player
endef

define Package/audiowrt-player-mpd/description
 Integrates the existing OpenWrt MPD instance into the AudioWRT playback
 registry without replacing MPD configuration or changing its ALSA output.
 A localhost listener is added to /etc/mpd.conf only when no existing local
 listener can be used.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) \
		-o $(PKG_BUILD_DIR)/audiowrt-player-mpd \
		$(PKG_BUILD_DIR)/audiowrt-player-mpd.c \
		$(TARGET_LDFLAGS) -lmpdclient -luci
endef

define Package/audiowrt-player-mpd/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-mpd $(1)/usr/bin/

	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt
	$(INSTALL_BIN) ./files/mpd-configure $(1)/usr/libexec/audiowrt/mpd-configure

	$(INSTALL_DIR) $(1)/usr/share/audiowrt/players
	$(INSTALL_DATA) ./files/mpd.manifest $(1)/usr/share/audiowrt/players/mpd.manifest

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt_mpd.config $(1)/etc/config/audiowrt_mpd
endef

define Package/audiowrt-player-mpd/conffiles
/etc/config/audiowrt_mpd
endef

define Package/audiowrt-player-mpd/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt/mpd-configure
/usr/libexec/audiowrt-playback-registry rebuild
endef

define Package/audiowrt-player-mpd/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-playback-registry exclude mpd
endef

$(eval $(call BuildPackage,audiowrt-player-mpd))
