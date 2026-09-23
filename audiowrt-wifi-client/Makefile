include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-wifi-client
PKG_VERSION:=1.0.4
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-wifi-client
  SECTION:=net
  CATEGORY:=Network
  TITLE:=AudioWRT reusable Wi-Fi client manager
  DEPENDS:=+audiowrt-config +uci +ubus +netifd +wifi-scripts +wpa-supplicant +rpcd-mod-iwinfo +iw +ip-tiny +jsonfilter
endef

define Package/audiowrt-wifi-client/description
 Reusable, opt-in Wi-Fi station and setup-AP manager for OpenWrt. Supports
 DHCP or manual IPv4 configuration without requiring the generic LuCI network
 module. Installing this package does not change network or wireless settings.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-wifi-client/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/libexec/audiowrt
	$(INSTALL_BIN) ./files/audiowrt-wifi-client $(1)/usr/sbin/audiowrt-wifi-client
	$(INSTALL_DATA) ./files/audiowrt-wifi-runtime $(1)/usr/libexec/audiowrt/wifi-runtime
endef

$(eval $(call BuildPackage,audiowrt-wifi-client))
