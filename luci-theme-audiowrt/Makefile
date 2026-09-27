include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-audiowrt
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-theme-audiowrt
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=4. Themes
  TITLE:=AudioWRT LuCI theme
  DEPENDS:=+luci-base +luci-theme-bootstrap
endef

define Package/luci-theme-audiowrt/description
 Lightweight monochrome AudioWRT theme for LuCI. The first iteration reuses
 Bootstrap's structural CSS and templates while overriding the visual language
 to match the AudioWRT provisioning UI.
endef

define Package/luci-theme-audiowrt/install
	$(INSTALL_DIR) $(1)/www/luci-static/audiowrt
	$(INSTALL_DATA) ./htdocs/luci-static/audiowrt/cascade.css $(1)/www/luci-static/audiowrt/cascade.css
	$(INSTALL_DATA) ./htdocs/luci-static/audiowrt/mobile.css $(1)/www/luci-static/audiowrt/mobile.css
	$(INSTALL_DATA) ./htdocs/luci-static/audiowrt/logo.svg $(1)/www/luci-static/audiowrt/logo.svg
	ln -s ../bootstrap/logo_48.png $(1)/www/luci-static/audiowrt/logo_48.png

	$(INSTALL_DIR) $(1)/usr/share/ucode/luci/template/themes/audiowrt
	ln -s ../bootstrap/header.ut $(1)/usr/share/ucode/luci/template/themes/audiowrt/header.ut
	ln -s ../bootstrap/footer.ut $(1)/usr/share/ucode/luci/template/themes/audiowrt/footer.ut
	ln -s ../bootstrap/sysauth.ut $(1)/usr/share/ucode/luci/template/themes/audiowrt/sysauth.ut

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/30_luci-theme-audiowrt $(1)/etc/uci-defaults/30_luci-theme-audiowrt
endef

define Package/luci-theme-audiowrt/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	uci -q delete luci.themes.AudioWRT
	[ "$$(uci -q get luci.main.mediaurlbase)" = "/luci-static/audiowrt" ] && \
		uci set luci.main.mediaurlbase='/luci-static/bootstrap'
	uci commit luci
}
endef

$(eval $(call BuildPackage,luci-theme-audiowrt))
