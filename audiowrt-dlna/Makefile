include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-dlna
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-dlna
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native modular DLNA renderer
  DEPENDS:=+libuci
endef

define Package/audiowrt-dlna/description
 Native DLNA/UPnP MediaRenderer with SSDP discovery, AVTransport,
 RenderingControl and ConnectionManager. Codec capabilities are discovered
 from installed audiowrt-player-* descriptors and may be overridden with
 custom player commands through UCI/LuCI.
endef

define Package/audiowrt-dlna/conffiles
/etc/config/audiowrt-dlna
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) \
		-o $(PKG_BUILD_DIR)/audiowrt-dlna \
		$(PKG_BUILD_DIR)/audiowrt-dlna.c \
		$(TARGET_LDFLAGS) -luci
endef

define Package/audiowrt-dlna/install
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-dlna $(1)/usr/libexec/audiowrt-dlna
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt-dlna.config $(1)/etc/config/audiowrt-dlna
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/audiowrt-dlna.init $(1)/etc/init.d/audiowrt-dlna
	$(INSTALL_DIR) $(1)/usr/share/audiowrt/dlna/players
endef

$(eval $(call BuildPackage,audiowrt-dlna))
