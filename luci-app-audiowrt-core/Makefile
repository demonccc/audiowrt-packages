include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-audiowrt-core
PKG_RELEASE:=4
PKG_LICENSE:=Apache-2.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-audiowrt-core
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=AudioWRT distribution management interface
  DEPENDS:=+luci-base
endef

define Package/luci-app-audiowrt-core/description
 Lightweight AudioWRT LuCI integration for distribution-specific navigation.
 Optional storage management is provided by audiowrt-storage-luci.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-audiowrt-core/install
	$(INSTALL_DIR) $(1)/
	$(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-audiowrt-core))
