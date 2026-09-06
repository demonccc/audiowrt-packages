include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-bluetooth
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-bluetooth
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT Bluetooth output integration
  DEPENDS:=+audiowrt-extensions +bluez-alsa +kmod-btusb
endef

define Package/audiowrt-bluetooth/description
 Adds Bluetooth speaker/headset pairing and A2DP output selection through BlueZ and BlueALSA.
endef

define Package/audiowrt-bluetooth/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/audiowrt-bluetooth $(1)/usr/sbin/audiowrt-bluetooth

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/audiowrt-bluetooth.defaults $(1)/etc/uci-defaults/85-audiowrt-bluetooth
endef

$(eval $(call BuildPackage,audiowrt-bluetooth))
