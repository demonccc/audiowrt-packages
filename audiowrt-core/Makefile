include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-core
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-core
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT core runtime
  DEPENDS:=+ubus +uci +uhttpd +umdns
endef

define Package/audiowrt-core/description
 Core runtime files and defaults shared by AudioWRT audio packages.
endef

define Package/audiowrt-core/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt.config $(1)/etc/config/audiowrt
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/audiowrt.init $(1)/etc/init.d/audiowrt
endef

$(eval $(call BuildPackage,audiowrt-core))
