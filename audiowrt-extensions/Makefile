include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-extensions
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-extensions
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT extension manager
  DEPENDS:=+audiowrt-core +audiowrt-storage +apk-mbedtls
endef

define Package/audiowrt-extensions/description
 Installs and configures optional audio engines using OpenWrt packages. External AudioWRT storage is used transparently when extroot is active.
endef

define Package/audiowrt-extensions/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/audiowrt-extensions $(1)/usr/sbin/audiowrt-extensions

	$(INSTALL_DIR) $(1)/usr/share/audiowrt
	$(INSTALL_DATA) ./files/extensions.catalog $(1)/usr/share/audiowrt/extensions.catalog

	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt/extensions
	$(INSTALL_BIN) ./files/mpd $(1)/usr/libexec/audiowrt/extensions/mpd
	$(INSTALL_BIN) ./files/airplay $(1)/usr/libexec/audiowrt/extensions/airplay
endef

$(eval $(call BuildPackage,audiowrt-extensions))
