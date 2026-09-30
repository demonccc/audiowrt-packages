include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-audio
PKG_VERSION:=1.0.1
PKG_RELEASE:=1
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

	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt
	$(INSTALL_DATA) ./files/audio-runtime $(1)/usr/libexec/audiowrt/audio-runtime

	$(INSTALL_DIR) $(1)/etc
	ln -sf /tmp/audiowrt/asound.conf $(1)/etc/asound.conf
endef

$(eval $(call BuildPackage,audiowrt-audio))
