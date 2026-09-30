include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-dlna-renderer
PKG_VERSION:=1.1.1
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-dlna-renderer
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT DLNA Renderer and discovery service
  DEPENDS:=+audiowrt-config +libaudiowrt-player +audiowrt-identity
  PROVIDES:=audiowrt-dlna
  CONFLICTS:=umdns audiowrt-umdns
endef

define Package/audiowrt-dlna-renderer/description
 Native AudioWRT DLNA Renderer. A single daemon provides DLNA/UPnP
 MediaRenderer functionality over SSDP, minimal authoritative mDNS/DNS-SD for
 the AudioWRT host and LuCI service, split UCI codec/player discovery, module-owned default player selection,
 fallback execution and runtime playback status. It does not require MPD, upmpdcli or
 a separate mDNS daemon.
endef

define Package/audiowrt-dlna-renderer/conffiles
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
		-Wall -Wextra \
		-o $(PKG_BUILD_DIR)/audiowrt-dlna-renderer \
		$(PKG_BUILD_DIR)/audiowrt-dlna.c \
		$(TARGET_LDFLAGS)
endef

define Package/audiowrt-dlna-renderer/install
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-dlna-renderer $(1)/usr/libexec/audiowrt-dlna-renderer
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt-dlna.config $(1)/etc/config/audiowrt-dlna
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/save-renderer $(1)/usr/libexec/audiowrt-save-dlna-renderer
	$(INSTALL_BIN) ./files/audiowrt-dlna.init $(1)/etc/init.d/audiowrt-dlna-renderer
endef

$(eval $(call BuildPackage,audiowrt-dlna-renderer))
