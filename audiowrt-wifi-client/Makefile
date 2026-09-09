include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-wifi-client
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-wifi-client
  SECTION:=net
  CATEGORY:=Network
  TITLE:=AudioWRT reusable Wi-Fi client manager
  DEPENDS:=+uci +ubus +rpcd-mod-iwinfo +netifd +wifi-scripts +wpad-basic-mbedtls +dnsmasq +umdns
endef

define Package/audiowrt-wifi-client/description
 Reusable opt-in Wi-Fi client, setup AP and recovery helper for OpenWrt.
 Installing this package does not alter network or wireless configuration until
 it is explicitly enabled or invoked.
endef

define Package/audiowrt-wifi-client/conffiles
/etc/config/audiowrt-wifi-client
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-wifi-client/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt-wifi-client.config $(1)/etc/config/audiowrt-wifi-client
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/audiowrt-wifi-client $(1)/usr/sbin/audiowrt-wifi-client
endef

$(eval $(call BuildPackage,audiowrt-wifi-client))
