include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-audiowrt-wifi-client
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-audiowrt-wifi-client
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=AudioWRT Wi-Fi client interface
  DEPENDS:=+luci-base +rpcd-mod-file +audiowrt-wifi-client
endef

define Package/luci-app-audiowrt-wifi-client/description
 Reusable opt-in LuCI page for scanning and configuring an OpenWrt device as a
 Wi-Fi client through the AudioWRT Wi-Fi client helper.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-audiowrt-wifi-client/install
	$(INSTALL_DIR) $(1)/www
	$(CP) ./htdocs/* $(1)/www/
	$(INSTALL_DIR) $(1)/
	$(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-audiowrt-wifi-client))
