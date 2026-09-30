# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-distro-branding
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-distro-branding
  SECTION:=audiowrt
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT distribution branding
  DEPENDS:=+base-files +luci-theme-audiowrt
endef

define Package/audiowrt-distro-branding/description
 Optional visual identity layer for the AudioWRT distribution. It installs the
 AudioWRT login/header logo, favicon and system banner on top of the reusable
 luci-theme-audiowrt package. Installing the theme alone keeps OpenWrt identity.
endef

define Build/Compile
endef

define Package/audiowrt-distro-branding/install
	$(INSTALL_DIR) $(1)/usr/share/audiowrt
	$(INSTALL_DATA) ./files/banner $(1)/usr/share/audiowrt/banner
	$(INSTALL_DIR) $(1)/www/luci-static/audiowrt-distro
	$(INSTALL_DATA) ./files/logo.svg $(1)/www/luci-static/audiowrt-distro/logo.svg
	ln -s logo.svg $(1)/www/luci-static/audiowrt-distro/favicon.svg
endef

define Package/audiowrt-distro-branding/postinst
#!/bin/sh
banner="$${IPKG_INSTROOT}/usr/share/audiowrt/banner"
target="$${IPKG_INSTROOT}/etc/banner"
[ -f "$${banner}" ] || exit 0
mkdir -p "$${IPKG_INSTROOT}/etc"
cp -f "$${banner}" "$${target}"
exit 0
endef

$(eval $(call BuildPackage,audiowrt-distro-branding))
