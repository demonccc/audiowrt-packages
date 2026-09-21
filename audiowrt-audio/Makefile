include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-audio
PKG_RELEASE:=5
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-audio
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT reusable audio runtime
  DEPENDS:=+uci
endef

define Package/audiowrt-audio/description
 Common AudioWRT audio state and output helpers. This package does not modify OpenWrt networking, firewall, DHCP or first-boot behavior.
endef

define Package/audiowrt-audio/conffiles
/etc/config/audiowrt-audio
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-audio/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt-audio.config $(1)/etc/config/audiowrt-audio

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/audiowrt-audio $(1)/usr/sbin/audiowrt-audio

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/audiowrt-audio.init $(1)/etc/init.d/audiowrt-audio

	$(INSTALL_DIR) $(1)/etc
	ln -sf /tmp/audiowrt/asound.conf $(1)/etc/asound.conf
endef

define Package/audiowrt-audio/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
mkdir -p /tmp/audiowrt
[ -e /tmp/audiowrt/asound.conf ] || : > /tmp/audiowrt/asound.conf
if [ ! -L /etc/asound.conf ] || [ "$(readlink /etc/asound.conf 2>/dev/null || true)" != "/tmp/audiowrt/asound.conf" ]; then
	rm -f /etc/asound.conf
	ln -s /tmp/audiowrt/asound.conf /etc/asound.conf
fi
/etc/init.d/audiowrt-audio enable >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,audiowrt-audio))
