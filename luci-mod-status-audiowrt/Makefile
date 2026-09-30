include $(TOPDIR)/rules.mk

PKG_NAME:=luci-mod-status-audiowrt
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0

LUCI_STATUS_DIR:=$(TOPDIR)/feeds/luci/modules/luci-mod-status

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-luci-minify.mk

define Package/luci-mod-status-audiowrt
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=2. Modules
  TITLE:=Lightweight LuCI status pages for AudioWRT
  DEPENDS:=+luci-base +libiwinfo +rpcd-mod-iwinfo
  PROVIDES:=luci-mod-status
  CONFLICTS:=luci-mod-status
endef

define Package/luci-mod-status-audiowrt/description
 Lightweight standalone replacement for luci-mod-status. It keeps the status
 pages useful on constrained OpenWrt devices, removes firewall/conntrack-only
 views, avoids the luci-mod-network dependency in Routing, and implements the
 Processes page without the BusyBox top applet. It is theme-independent.
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/src
	$(CP) $(LUCI_STATUS_DIR)/src/Makefile $(PKG_BUILD_DIR)/src/
	$(CP) $(LUCI_STATUS_DIR)/src/luci-bwc.c $(PKG_BUILD_DIR)/src/
endef

define Build/Configure
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/src compile \
		CC="$(TARGET_CC)" \
		CPPFLAGS="$(TARGET_CPPFLAGS)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		FPIC="$(FPIC)"
endef

define Package/luci-mod-status-audiowrt/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/status/include
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/view/status/index.js $(1)/www/luci-static/resources/view/status/index.js
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/view/status/routes.js $(1)/www/luci-static/resources/view/status/routes.js
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/view/status/syslog.js $(1)/www/luci-static/resources/view/status/syslog.js
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/view/status/channel_analysis.js $(1)/www/luci-static/resources/view/status/channel_analysis.js
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/view/status/load.js $(1)/www/luci-static/resources/view/status/load.js
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/view/status/bandwidth.js $(1)/www/luci-static/resources/view/status/bandwidth.js
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/view/status/wireless.js $(1)/www/luci-static/resources/view/status/wireless.js
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/status/processes.js $(1)/www/luci-static/resources/view/status/processes.js

	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/view/status/include/10_system.js $(1)/www/luci-static/resources/view/status/include/10_system.js
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/view/status/include/20_memory.js $(1)/www/luci-static/resources/view/status/include/20_memory.js
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/view/status/include/25_storage.js $(1)/www/luci-static/resources/view/status/include/25_storage.js
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/view/status/include/30_network.js $(1)/www/luci-static/resources/view/status/include/30_network.js
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/view/status/include/60_wifi.js $(1)/www/luci-static/resources/view/status/include/60_wifi.js
	$(call AudioWRT/MinifyJS,$(1)/www)

	$(INSTALL_DIR) $(1)/www/luci-static/resources/svg
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/svg/load.svg $(1)/www/luci-static/resources/svg/load.svg
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/svg/bandwidth.svg $(1)/www/luci-static/resources/svg/bandwidth.svg
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/svg/wireless.svg $(1)/www/luci-static/resources/svg/wireless.svg
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/svg/wifirate.svg $(1)/www/luci-static/resources/svg/wifirate.svg
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/htdocs/luci-static/resources/svg/channel_analysis.svg $(1)/www/luci-static/resources/svg/channel_analysis.svg

	$(INSTALL_DIR) $(1)/usr/share/ucode/luci/template/admin_status
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/ucode/template/admin_status/index.ut $(1)/usr/share/ucode/luci/template/admin_status/index.ut

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-mod-status-audiowrt.json $(1)/usr/share/luci/menu.d/luci-mod-status-audiowrt.json

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(LUCI_STATUS_DIR)/root/usr/share/rpcd/acl.d/luci-mod-status-index.json $(1)/usr/share/rpcd/acl.d/luci-mod-status-index.json
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-mod-status-audiowrt.json $(1)/usr/share/rpcd/acl.d/luci-mod-status-audiowrt.json

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/luci-bwc $(1)/usr/bin/luci-bwc

	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./root/usr/libexec/audiowrt-process-list $(1)/usr/libexec/audiowrt-process-list
endef

$(eval $(call BuildPackage,luci-mod-status-audiowrt))
