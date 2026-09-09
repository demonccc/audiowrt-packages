include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-audio
PKG_RELEASE:=3
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
 Common AudioWRT audio state and output helpers. This package does not modify OpenWrt networking, firewall, DHCP or first-boot behavior. The OpenWrt system hostname is the canonical AudioWRT device name.
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
endef

$(eval $(call BuildPackage,audiowrt-audio))
