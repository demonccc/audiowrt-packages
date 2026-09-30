include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-mpd
PKG_VERSION:=1.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-mpd
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT MPD player integration
  DEPENDS:=+mpd
endef

define Package/audiowrt-player-mpd/description
 Configures whichever package provides the OpenWrt mpd capability for use as an
 AudioWRT playback backend. The package does not build or replace MPD: mpd-mini
 and mpd-full remain independently installable OpenWrt packages and both can
 satisfy the mpd dependency.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-player-mpd/install
	$(INSTALL_DIR) $(1)/etc/init.d $(1)/etc/rc.d
	$(INSTALL_BIN) ./files/mpd-runtime.init $(1)/etc/init.d/audiowrt-mpd-runtime
	ln -s ../init.d/audiowrt-mpd-runtime $(1)/etc/rc.d/S92audiowrt-mpd-runtime

	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt
	$(INSTALL_BIN) ./files/mpd $(1)/usr/libexec/audiowrt/mpd

	$(INSTALL_DIR) $(1)/usr/share/audiowrt
	$(INSTALL_DATA) ./files/mpd.conf $(1)/usr/share/audiowrt/mpd.conf
endef

define Package/audiowrt-player-mpd/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt/mpd configure
endef

$(eval $(call BuildPackage,audiowrt-player-mpd))
