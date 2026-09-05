include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-airplay
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-airplay
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT AirPlay integration
  DEPENDS:=+audiowrt-usb-audio +shairport-sync-mini
endef

define Package/audiowrt-airplay/description
 Configures Shairport Sync as an AirPlay receiver using AudioWRT's selected USB audio output.
endef

define Package/audiowrt-airplay/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/audiowrt-airplay.defaults $(1)/etc/uci-defaults/70-audiowrt-airplay
endef

$(eval $(call BuildPackage,audiowrt-airplay))
