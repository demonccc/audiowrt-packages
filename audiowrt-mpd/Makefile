include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-mpd
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-mpd
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT MPD integration
  DEPENDS:=+audiowrt-usb-audio +mpd-mini
endef

define Package/audiowrt-mpd/description
 Configures Music Player Daemon for AudioWRT local and HTTP playback through the selected USB audio output.
endef

define Package/audiowrt-mpd/install
	$(INSTALL_DIR) $(1)/usr/share/audiowrt
	$(INSTALL_CONF) ./files/mpd.conf $(1)/usr/share/audiowrt/mpd.conf

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/audiowrt-mpd.defaults $(1)/etc/uci-defaults/60-audiowrt-mpd
endef

$(eval $(call BuildPackage,audiowrt-mpd))
