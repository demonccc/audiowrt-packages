include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-audiowrt
PKG_RELEASE:=2
PKG_LICENSE:=Apache-2.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-audiowrt
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=AudioWRT web interface
  DEPENDS:=+luci-base +rpcd-mod-file +audiowrt-core +audiowrt-usb-audio +audiowrt-storage +audiowrt-extensions
endef

define Package/luci-app-audiowrt/description
 Focused LuCI interface for AudioWRT status, extension storage and optional audio engines.
endef

define Build/Compile
endef

define Package/luci-app-audiowrt/install
	$(INSTALL_DIR) $(1)/www
	$(CP) ./htdocs/* $(1)/www/
	$(INSTALL_DIR) $(1)/
	$(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-audiowrt))
