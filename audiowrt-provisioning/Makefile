include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-provisioning
PKG_VERSION:=1.0.6
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-luci-minify.mk

define Package/audiowrt-provisioning
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT runtime provisioning
  DEPENDS:=+audiowrt-core +audiowrt-audio +audiowrt-wifi-client +hostapd +audiowrt-udhcpd +ubus +uci +uhttpd +luci-base +jsonfilter
endef

define Package/audiowrt-provisioning/description
 AudioWRT runtime provisioning for device name, Wi-Fi client setup and administrator password. Reusable Wi-Fi behavior is delegated to audiowrt-wifi-client; boot-time setup state remains in tmpfs.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
	$(call AudioWRT/BuildJsMin)
endef

define Package/audiowrt-provisioning/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/audiowrtctl $(1)/usr/sbin/audiowrtctl

	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt
	$(INSTALL_BIN) ./files/audiowrt-provision $(1)/usr/libexec/audiowrt/provision-wifi
	$(INSTALL_BIN) ./files/setup-ap $(1)/usr/libexec/audiowrt/setup-ap
	$(INSTALL_BIN) ./files/provision-web $(1)/usr/libexec/audiowrt/provision-web
	$(INSTALL_BIN) ./files/provision-supervisor $(1)/usr/libexec/audiowrt/provision-supervisor
	$(INSTALL_BIN) ./files/audiowrt-setup-ssid $(1)/usr/libexec/audiowrt/setup-ssid

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/audiowrt-provisioning.init $(1)/etc/init.d/audiowrt-provisioning
	$(INSTALL_DIR) $(1)/etc/rc.d
	ln -s ../init.d/audiowrt-provisioning $(1)/etc/rc.d/S99audiowrt-provisioning

	$(INSTALL_DIR) $(1)/etc/hotplug.d/button
	$(INSTALL_BIN) ./files/audiowrt-button.hotplug $(1)/etc/hotplug.d/button/90-audiowrt-provision

	$(INSTALL_DIR) $(1)/etc/sysctl.d
	$(INSTALL_CONF) ./files/99-audiowrt.conf $(1)/etc/sysctl.d/99-audiowrt.conf

	$(INSTALL_DIR) $(1)/www
	$(INSTALL_DATA) ./files/audiowrt.html $(1)/www/audiowrt.html
	python3 $(TOPDIR)/feeds/audiowrt/include/audiowrt-html-minify.py $(AUDIOWRT_JSMIN) $(1)/www/audiowrt.html

	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_BIN) ./files/audiowrt-status.cgi $(1)/www/cgi-bin/audiowrt-status
	$(INSTALL_BIN) ./files/audiowrt-scan.cgi $(1)/www/cgi-bin/audiowrt-scan
	$(INSTALL_BIN) ./files/audiowrt-radios.cgi $(1)/www/cgi-bin/audiowrt-radios
	$(INSTALL_BIN) ./files/audiowrt-provision.cgi $(1)/www/cgi-bin/audiowrt-provision
endef

$(eval $(call BuildPackage,audiowrt-provisioning))
