include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-airplay
PKG_RELEASE:=4
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-airplay
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT AirPlay integration
  DEPENDS:=+audiowrt-extensions +shairport-sync-mini
endef

define Package/audiowrt-airplay/description
 Installs Shairport Sync and configures it to use the AudioWRT-selected ALSA output without changing OpenWrt networking.
endef

define Package/audiowrt-airplay/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/audiowrt-airplay.defaults $(1)/etc/uci-defaults/70-audiowrt-airplay
endef

$(eval $(call BuildPackage,audiowrt-airplay))
