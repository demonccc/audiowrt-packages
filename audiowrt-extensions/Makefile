include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-extensions
PKG_RELEASE:=4
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-extensions
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT audio extension manager
  DEPENDS:=+audiowrt-audio +apk-mbedtls
endef

define Package/audiowrt-extensions/description
 Installs, removes and configures optional AudioWRT audio services without changing OpenWrt network or router configuration.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-extensions/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/audiowrt-extensions $(1)/usr/sbin/audiowrt-extensions

	$(INSTALL_DIR) $(1)/usr/share/audiowrt
	$(INSTALL_DATA) ./files/extensions.catalog $(1)/usr/share/audiowrt/extensions.catalog

	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt/extensions
	$(INSTALL_BIN) ./files/mpd $(1)/usr/libexec/audiowrt/extensions/mpd
	$(INSTALL_BIN) ./files/airplay $(1)/usr/libexec/audiowrt/extensions/airplay
	$(INSTALL_BIN) ./files/spotify $(1)/usr/libexec/audiowrt/extensions/spotify
endef

$(eval $(call BuildPackage,audiowrt-extensions))
