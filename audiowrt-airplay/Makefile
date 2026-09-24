include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-airplay
PKG_VERSION:=1.0.2
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-airplay
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT AirPlay integration
  DEPENDS:=+audiowrt-config +shairport-sync-mini
endef

define Package/audiowrt-airplay/description
 Installs Shairport Sync and configures it to use the AudioWRT-selected ALSA output without changing OpenWrt networking.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-airplay/install
	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt
	$(INSTALL_BIN) ./files/airplay $(1)/usr/libexec/audiowrt/airplay

	$(INSTALL_DIR) $(1)/usr/share/audiowrt
	$(INSTALL_DATA) ./files/airplay.settings $(1)/usr/share/audiowrt/airplay.settings
endef

define Package/audiowrt-airplay/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt/airplay configure
endef

$(eval $(call BuildPackage,audiowrt-airplay))
