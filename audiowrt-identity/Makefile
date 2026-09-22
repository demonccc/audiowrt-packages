include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-identity
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-identity
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=AudioWRT volatile device identity
endef

define Package/audiowrt-identity/description
 Recreates a deterministic device UUID in /tmp/audiowrt/uuid at boot.
 Services share this identity without storing generated state on flash.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-identity/install
	$(INSTALL_DIR) $(1)/etc/init.d $(1)/etc/rc.d
	$(INSTALL_BIN) ./files/audiowrt-identity.init $(1)/etc/init.d/audiowrt-identity
	$(LN) ../init.d/audiowrt-identity $(1)/etc/rc.d/S11audiowrt-identity
endef

$(eval $(call BuildPackage,audiowrt-identity))
