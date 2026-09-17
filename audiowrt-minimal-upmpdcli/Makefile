# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

AUDIOWRT_DERIVED_NAME:=audiowrt-minimal-upmpdcli
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/packages/sound/upmpdcli/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk

PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/meson.mk

define Package/audiowrt-minimal-upmpdcli
  SECTION:=sound
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT minimal UPnP/DLNA renderer
  URL:=https://www.lesbonscomptes.com/upmpdcli
  DEPENDS:=+libupnpp +libmpdclient +jsoncpp +mpd
  USERID:=upmpdcli=89:upmpdcli=89
  PROVIDES:=upmpdcli
  CONFLICTS:=upmpdcli
endef

define Package/audiowrt-minimal-upmpdcli/description
 upmpdcli derived from the selected OpenWrt release and packaged for the
 AudioWRT minimal renderer path. It exposes UPnP AV/DLNA only, talks to the
 local MPD backend, disables OpenHome, and advertises only FLAC and MP3.
endef

define Package/audiowrt-minimal-upmpdcli/conffiles
/etc/config/upmpdcli
/etc/upmpdcli.conf
endef

MESON_ARGS += -Dscctl=disabled

define Package/audiowrt-minimal-upmpdcli/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/upmpdcli $(1)/usr/bin/

	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_CONF) ./files/upmpdcli.conf $(1)/etc/upmpdcli.conf

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/upmpdcli.config $(1)/etc/config/upmpdcli

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(AUDIOWRT_DERIVED_FILES_DIR)/upmpdcli.init $(1)/etc/init.d/upmpdcli

	$(INSTALL_DIR) $(1)/usr/share/upmpdcli
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/usr/share/upmpdcli/AVTransport.xml $(1)/usr/share/upmpdcli/
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/usr/share/upmpdcli/ConnectionManager.xml $(1)/usr/share/upmpdcli/
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/usr/share/upmpdcli/RenderingControl.xml $(1)/usr/share/upmpdcli/
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/usr/share/upmpdcli/description.xml $(1)/usr/share/upmpdcli/
	$(INSTALL_DATA) $(AUDIOWRT_DERIVED_FILES_DIR)/upmpdcli.png $(1)/usr/share/upmpdcli/icon.png
	$(INSTALL_DATA) ./files/protocolinfo.txt $(1)/usr/share/upmpdcli/protocolinfo.txt
endef

$(eval $(call BuildPackage,audiowrt-minimal-upmpdcli))
