include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-provisioning
PKG_RELEASE:=4
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-provisioning
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT first-boot provisioning
  DEPENDS:=+audiowrt-core +audiowrt-audio +audiowrt-wifi-client +ubus +uci +uhttpd +luci-base +jsonfilter
endef

define Package/audiowrt-provisioning/description
 AudioWRT-only first-boot provisioning for device name, Wi-Fi client setup and administrator password. Reusable Wi-Fi behavior is delegated to audiowrt-wifi-client.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-provisioning/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/audiowrtctl $(1)/usr/sbin/audiowrtctl

	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt
	$(INSTALL_BIN) ./files/audiowrt-provision $(1)/usr/libexec/audiowrt/provision-wifi

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/audiowrt-provisioning-firstboot $(1)/etc/uci-defaults/10-audiowrt-provisioning

	$(INSTALL_DIR) $(1)/etc/hotplug.d/button
	$(INSTALL_BIN) ./files/audiowrt-button.hotplug $(1)/etc/hotplug.d/button/90-audiowrt-provision

	$(INSTALL_DIR) $(1)/etc/sysctl.d
	$(INSTALL_CONF) ./files/99-audiowrt.conf $(1)/etc/sysctl.d/99-audiowrt.conf

	$(INSTALL_DIR) $(1)/www
	$(INSTALL_DATA) ./files/audiowrt.html $(1)/www/audiowrt.html

	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_BIN) ./files/audiowrt-status.cgi $(1)/www/cgi-bin/audiowrt-status
	$(INSTALL_BIN) ./files/audiowrt-scan.cgi $(1)/www/cgi-bin/audiowrt-scan
	$(INSTALL_BIN) ./files/audiowrt-radios.cgi $(1)/www/cgi-bin/audiowrt-radios
	$(INSTALL_BIN) ./files/audiowrt-provision.cgi $(1)/www/cgi-bin/audiowrt-provision
endef

$(eval $(call BuildPackage,audiowrt-provisioning))
