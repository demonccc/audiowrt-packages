include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-audiowrt-renderer
PKG_VERSION:=1.1.1
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-audiowrt-renderer
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=AudioWRT renderer and discovery interface
  DEPENDS:=+luci-base +rpcd-mod-file +luci-app-audiowrt +audiowrt-renderer
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-audiowrt-renderer/install
	$(INSTALL_DIR) $(1)/www
	$(CP) ./htdocs/* $(1)/www/
	$(INSTALL_DIR) $(1)/
	$(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-audiowrt-renderer))
