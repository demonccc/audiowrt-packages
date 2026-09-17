include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-dlna
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-dlna
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native DLNA renderer
  DEPENDS:=+libubox +libubus +libuci +umdns
endef

define Package/audiowrt-dlna/description
 Native AudioWRT DLNA renderer foundation. Codec/player support is discovered
 from descriptor files installed by audiowrt-player-* packages. User-defined
 player mappings override autodetected mappings without removing them.
endef

define Package/audiowrt-dlna/conffiles
/etc/config/audiowrt-dlna
endef

define Build/Compile
endef

define Package/audiowrt-dlna/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt-dlna.config $(1)/etc/config/audiowrt-dlna
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/audiowrt-dlna.init $(1)/etc/init.d/audiowrt-dlna
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/audiowrt-dlna $(1)/usr/libexec/audiowrt-dlna
	$(INSTALL_DIR) $(1)/usr/share/audiowrt/dlna/players
	$(INSTALL_DIR) $(1)/var/run/audiowrt-dlna
endef

$(eval $(call BuildPackage,audiowrt-dlna))
