include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-config
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all
include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-config
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=AudioWRT isolated explicit configuration saves
  DEPENDS:=+uci
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-config/install
	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt
	$(INSTALL_DATA) ./files/config-save $(1)/usr/libexec/audiowrt/config-save
endef

$(eval $(call BuildPackage,audiowrt-config))
