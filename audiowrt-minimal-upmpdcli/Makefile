# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-minimal-upmpdcli
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-minimal-upmpdcli
  SECTION:=sound
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT minimal UPnP/DLNA renderer profile
  DEPENDS:=+upmpdcli +mpd-mini
endef

define Package/audiowrt-minimal-upmpdcli/description
 Runtime profile for the exact upmpdcli and mpd-mini binaries shipped by the
 selected OpenWrt release. AudioWRT disables OpenHome, keeps MPD on loopback,
 and replaces protocolinfo with the constrained FLAC/MP3 renderer profile.
 No upstream source or dependency graph is rebuilt.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-minimal-upmpdcli/install
	$(INSTALL_DIR) $(1)/usr/share/audiowrt/upmpdcli
	$(INSTALL_DATA) ./files/upmpdcli.conf $(1)/usr/share/audiowrt/upmpdcli/upmpdcli.conf
	$(INSTALL_DATA) ./files/upmpdcli.config $(1)/usr/share/audiowrt/upmpdcli/upmpdcli.config
	$(INSTALL_DATA) ./files/protocolinfo.txt $(1)/usr/share/audiowrt/upmpdcli/protocolinfo.txt
endef

define Package/audiowrt-minimal-upmpdcli/postinst
#!/bin/sh
root="$${IPKG_INSTROOT:-}"
src="$${root}/usr/share/audiowrt/upmpdcli"
[ -d "$${src}" ] || exit 0
mkdir -p "$${root}/etc/config" "$${root}/usr/share/upmpdcli"
cp "$${src}/upmpdcli.conf" "$${root}/etc/upmpdcli.conf"
cp "$${src}/upmpdcli.config" "$${root}/etc/config/upmpdcli"
cp "$${src}/protocolinfo.txt" "$${root}/usr/share/upmpdcli/protocolinfo.txt"
exit 0
endef

$(eval $(call BuildPackage,audiowrt-minimal-upmpdcli))
