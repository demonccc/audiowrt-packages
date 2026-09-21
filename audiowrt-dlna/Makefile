include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-renderer
PKG_VERSION:=1.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-renderer
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native network renderer and discovery service
  PROVIDES:=audiowrt-dlna
  CONFLICTS:=umdns audiowrt-umdns
endef

define Package/audiowrt-renderer/description
 Native AudioWRT network renderer. A single daemon provides DLNA/UPnP
 MediaRenderer functionality over SSDP, minimal authoritative mDNS/DNS-SD for
 the AudioWRT host and LuCI service, split UCI codec/player discovery, module-owned default player selection,
 fallback execution and runtime playback status. It does not require MPD, upmpdcli or
 a separate mDNS daemon.
endef

define Package/audiowrt-renderer/conffiles
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
		-o $(PKG_BUILD_DIR)/audiowrt-renderer \
		$(PKG_BUILD_DIR)/audiowrt-dlna.c \
		$(TARGET_LDFLAGS)
endef

define Package/audiowrt-renderer/install
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-renderer $(1)/usr/libexec/audiowrt-renderer
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt-dlna.config $(1)/etc/config/audiowrt-dlna
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/audiowrt-dlna.init $(1)/etc/init.d/audiowrt-renderer
endef

$(eval $(call BuildPackage,audiowrt-renderer))
