include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-core
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-core
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT distribution core
  DEPENDS:=+uci +audiowrt-audio
endef

define Package/audiowrt-core/description
 AudioWRT distribution identity and appliance state. This package is intended for AudioWRT firmware images, not as an add-on for existing OpenWrt routers.
endef

define Package/audiowrt-core/conffiles
/etc/config/audiowrt
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-core/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt.config $(1)/etc/config/audiowrt

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/audiowrt.init $(1)/etc/init.d/audiowrt

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/audiowrt-core-firstboot $(1)/etc/uci-defaults/05-audiowrt-core
endef

$(eval $(call BuildPackage,audiowrt-core))
