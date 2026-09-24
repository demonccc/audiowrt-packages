include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-audiowrt-network-client
PKG_VERSION:=1.0.1
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-audiowrt-network-client
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=AudioWRT network client interface
  DEPENDS:=+luci-base +rpcd-mod-file +audiowrt-network-client +audiowrt-wifi-client
endef

define Package/luci-app-audiowrt-network-client/description
 Unified AudioWRT network client page for Ethernet and Wi-Fi status and
 configuration without requiring the generic LuCI network module.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-audiowrt-network-client/install
	$(INSTALL_DIR) $(1)/www
	$(CP) ./htdocs/* $(1)/www/
	$(INSTALL_DIR) $(1)/
	$(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-audiowrt-network-client))
