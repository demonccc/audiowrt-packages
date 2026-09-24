include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-mpd
PKG_VERSION:=1.0.2
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-mpd
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT MPD integration
  DEPENDS:=+mpd
endef

define Package/audiowrt-mpd/description
 Installs MPD integration and configures whichever MPD provider the selected
 AudioWRT flavor supplies. Minimal flavors use audiowrt-minimal-mpd; larger
 flavors can continue using the OpenWrt MPD implementation.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-mpd/install
	$(INSTALL_DIR) $(1)/etc/init.d $(1)/etc/rc.d
	$(INSTALL_BIN) ./files/mpd-runtime.init $(1)/etc/init.d/audiowrt-mpd-runtime
	ln -s ../init.d/audiowrt-mpd-runtime $(1)/etc/rc.d/S92audiowrt-mpd-runtime

	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt
	$(INSTALL_BIN) ./files/mpd $(1)/usr/libexec/audiowrt/mpd

	$(INSTALL_DIR) $(1)/usr/share/audiowrt
	$(INSTALL_DATA) ./files/mpd.conf $(1)/usr/share/audiowrt/mpd.conf
endef

define Package/audiowrt-mpd/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt/mpd configure
endef

$(eval $(call BuildPackage,audiowrt-mpd))
