include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-audiowrt
PKG_RELEASE:=5
PKG_LICENSE:=Apache-2.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-audiowrt
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=AudioWRT audio management interface
  DEPENDS:=+luci-base +rpcd-mod-file +audiowrt-audio +audiowrt-extensions
endef

define Package/luci-app-audiowrt/description
 Reusable LuCI interface for AudioWRT audio outputs and music-service extensions.
 It also contributes an AudioWRT section to OpenWrt's extensible Status Overview
 when luci-mod-status is installed. It does not modify router configuration.
endef

define Build/Prepare
endef

define Build/Configure
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
