# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-branding
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-branding
  SECTION:=audiowrt
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT system branding metadata
  PKGARCH:=all
  DEPENDS:=+base-files
endef

define Package/audiowrt-branding/description
 Installs AudioWRT system branding metadata such as the login banner.
endef

define Build/Compile
endef

define Package/audiowrt-branding/install
	$(INSTALL_DIR) $(1)/usr/share/audiowrt
	$(INSTALL_DATA) ./files/banner $(1)/usr/share/audiowrt/banner
endef

define Package/audiowrt-branding/postinst
#!/bin/sh
banner="$${IPKG_INSTROOT}/usr/share/audiowrt/banner"
target="$${IPKG_INSTROOT}/etc/banner"
[ -f "$${banner}" ] || exit 0
mkdir -p "$${IPKG_INSTROOT}/etc"
cp -f "$${banner}" "$${target}"
exit 0
endef

$(eval $(call BuildPackage,audiowrt-branding))
