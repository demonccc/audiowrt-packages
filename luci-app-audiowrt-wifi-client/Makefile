include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-audiowrt-wifi-client
PKG_VERSION:=1.0.2
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-audiowrt-wifi-client
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=AudioWRT Network Client compatibility package
  DEPENDS:=+luci-app-audiowrt-network-client
endef

define Package/luci-app-audiowrt-wifi-client/description
 Compatibility package for existing AudioWRT profiles. The Wi-Fi-only LuCI
 page has been replaced by the unified Network Client page.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-audiowrt-wifi-client/install
endef

$(eval $(call BuildPackage,luci-app-audiowrt-wifi-client))
