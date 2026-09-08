include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-mpd
PKG_RELEASE:=5
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-mpd
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT MPD integration
  DEPENDS:=+audiowrt-extensions +mpd-mini
endef

define Package/audiowrt-mpd/description
 Installs MPD and configures it to use the AudioWRT-selected ALSA output without changing OpenWrt networking.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-mpd/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/audiowrt-mpd.defaults $(1)/etc/uci-defaults/60-audiowrt-mpd
endef

$(eval $(call BuildPackage,audiowrt-mpd))
