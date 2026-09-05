include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-core
PKG_RELEASE:=3
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-core
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT core runtime and provisioning
  DEPENDS:=+ubus +uci +uhttpd +umdns +dnsmasq +wpad-basic-mbedtls +iwinfo +netifd +wifi-scripts
endef

define Package/audiowrt-core/description
 Core AudioWRT runtime, first-boot network defaults and Wi-Fi provisioning.
endef

define Package/audiowrt-core/conffiles
/etc/config/audiowrt
endef

define Package/audiowrt-core/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt.config $(1)/etc/config/audiowrt

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/audiowrt.init $(1)/etc/init.d/audiowrt

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/audiowrtctl $(1)/usr/sbin/audiowrtctl

	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt
	$(INSTALL_BIN) ./files/audiowrt-provision $(1)/usr/libexec/audiowrt/provision-wifi

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/audiowrt-firstboot $(1)/etc/uci-defaults/10-audiowrt-firstboot

	$(INSTALL_DIR) $(1)/etc/hotplug.d/button
	$(INSTALL_BIN) ./files/audiowrt-button.hotplug $(1)/etc/hotplug.d/button/90-audiowrt-provision

	$(INSTALL_DIR) $(1)/etc/sysctl.d
	$(INSTALL_CONF) ./files/99-audiowrt.conf $(1)/etc/sysctl.d/99-audiowrt.conf

	$(INSTALL_DIR) $(1)/www
	$(INSTALL_DATA) ./files/audiowrt.html $(1)/www/audiowrt.html

	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_BIN) ./files/audiowrt-status.cgi $(1)/www/cgi-bin/audiowrt-status
	$(INSTALL_BIN) ./files/audiowrt-provision.cgi $(1)/www/cgi-bin/audiowrt-provision
endef

$(eval $(call BuildPackage,audiowrt-core))
