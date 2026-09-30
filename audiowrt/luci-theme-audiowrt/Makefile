include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-audiowrt
PKG_VERSION:=0.2.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKGARCH:=all

LUCI_BOOTSTRAP_DIR:=$(TOPDIR)/feeds/luci/themes/luci-theme-bootstrap
AUDIOWRT_THEME_BUILD_DIR=$(PKG_BUILD_DIR)/audiowrt-theme

include $(INCLUDE_DIR)/package.mk

define Package/luci-theme-audiowrt
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=4. Themes
  TITLE:=AudioWRT LuCI theme
  DEPENDS:=+luci-base
endef

define Package/luci-theme-audiowrt/description
 Reusable standalone monochrome LuCI theme maintained by AudioWRT. Installing
 the theme alone keeps OpenWrt identity; AudioWRT logo/favicon assets are
 provided only by the optional audiowrt-distro-branding package.
endef

define Build/Compile
	rm -rf $(AUDIOWRT_THEME_BUILD_DIR)
	$(INSTALL_DIR) $(AUDIOWRT_THEME_BUILD_DIR)
	python3 ./minify-assets.py css $(AUDIOWRT_THEME_BUILD_DIR)/cascade.css \
		$(LUCI_BOOTSTRAP_DIR)/htdocs/luci-static/bootstrap/cascade.css \
		./htdocs/luci-static/audiowrt/cascade.css \
		./htdocs/luci-static/audiowrt/override.css \
		./htdocs/luci-static/audiowrt/fixes.css
	python3 ./minify-assets.py css $(AUDIOWRT_THEME_BUILD_DIR)/mobile.css \
		./htdocs/luci-static/audiowrt/mobile.css
	python3 ./minify-assets.py js $(AUDIOWRT_THEME_BUILD_DIR)/menu.js \
		./htdocs/luci-static/audiowrt/menu.js
endef

define Package/luci-theme-audiowrt/install
	$(INSTALL_DIR) $(1)/www/luci-static/audiowrt
	$(INSTALL_DATA) $(AUDIOWRT_THEME_BUILD_DIR)/cascade.css $(1)/www/luci-static/audiowrt/cascade.css
	$(INSTALL_DATA) $(AUDIOWRT_THEME_BUILD_DIR)/mobile.css $(1)/www/luci-static/audiowrt/mobile.css
	$(INSTALL_DATA) $(AUDIOWRT_THEME_BUILD_DIR)/menu.js $(1)/www/luci-static/audiowrt/menu.js

	$(INSTALL_DIR) $(1)/usr/share/ucode/luci/template/themes/audiowrt
	$(INSTALL_DATA) ./ucode/template/themes/audiowrt/header.ut $(1)/usr/share/ucode/luci/template/themes/audiowrt/header.ut
	$(INSTALL_DATA) ./ucode/template/themes/audiowrt/footer.ut $(1)/usr/share/ucode/luci/template/themes/audiowrt/footer.ut
	$(INSTALL_DATA) ./ucode/template/themes/audiowrt/sysauth.ut $(1)/usr/share/ucode/luci/template/themes/audiowrt/sysauth.ut

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/30_luci-theme-audiowrt $(1)/etc/uci-defaults/30_luci-theme-audiowrt
endef

define Package/luci-theme-audiowrt/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	uci -q delete luci.themes.AudioWRT
	if [ "$$(uci -q get luci.main.mediaurlbase)" = "/luci-static/audiowrt" ]; then
		if [ -d /www/luci-static/bootstrap ]; then
			uci set luci.main.mediaurlbase='/luci-static/bootstrap'
		else
			uci -q delete luci.main.mediaurlbase
		fi
	fi
	uci commit luci
}
endef

$(eval $(call BuildPackage,luci-theme-audiowrt))
