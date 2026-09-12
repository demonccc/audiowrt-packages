include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-storage-luci
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-storage-luci
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=AudioWRT storage management interface
  DEPENDS:=+luci-base +rpcd-mod-file +luci-app-audiowrt +audiowrt-storage
endef

define Package/audiowrt-storage-luci/description
 Optional LuCI interface for AudioWRT external USB extension storage.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-storage-luci/install
	$(INSTALL_DIR) $(1)/www
	$(CP) ./htdocs/* $(1)/www/
	$(INSTALL_DIR) $(1)/
	$(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,audiowrt-storage-luci))
