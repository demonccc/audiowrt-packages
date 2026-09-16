# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-wpa-supplicant
PKG_VERSION:=1
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-wpa-supplicant
  SECTION:=net
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT client-only WPA supplicant
  DEPENDS:=+wpa-supplicant-mbedtls
endef

define Package/audiowrt-wpa-supplicant/description
 Selects the OpenWrt mbedTLS WPA supplicant without the hostapd/AP half of
 wpad. AudioWRT uses Wi-Fi only as a station, so AP, mesh and combined wpad
 functionality are intentionally excluded from constrained images.
endef

define Build/Compile
endef

define Package/audiowrt-wpa-supplicant/install
	true
endef

$(eval $(call BuildPackage,audiowrt-wpa-supplicant))
