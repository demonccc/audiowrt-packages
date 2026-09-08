include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-spotify
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-spotify
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT Spotify Connect integration
  DEPENDS:=+audiowrt-extensions +librespot
endef

define Package/audiowrt-spotify/description
 Installs librespot and exposes the device as a Spotify Connect speaker using the selected ALSA output.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-spotify/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/audiowrt-spotify.defaults $(1)/etc/uci-defaults/80-audiowrt-spotify
endef

$(eval $(call BuildPackage,audiowrt-spotify))
