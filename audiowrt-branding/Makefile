# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-branding
PKG_VERSION:=1
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-branding
  SECTION:=audiowrt
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT system branding metadata
  PKGARCH:=all
endef

define Package/audiowrt-branding/description
 Installs AudioWRT system branding metadata such as the login banner.
endef

define Build/Compile
endef

define Package/audiowrt-branding/install
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_DATA) ./files/banner $(1)/etc/banner
endef

$(eval $(call BuildPackage,audiowrt-branding))
