include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-lpcm
PKG_VERSION:=1.0.3
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-lpcm
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native DLNA LPCM player
  DEPENDS:=+libaudiowrt-player +libpthread
endef

define Package/audiowrt-player-lpcm/description
 Native AudioWRT DLNA LPCM/L16 player. The DLNA metadata-provided sample rate
 and channel count are honored; samples are converted from network byte order
 and written directly to ALSA.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) \
		-I$(STAGING_DIR)/usr/include/audiowrt \
		-o $(PKG_BUILD_DIR)/audiowrt-player-lpcm \
		$(PKG_BUILD_DIR)/audiowrt-player-lpcm.c \
		$(TARGET_LDFLAGS) -Wl,-rpath-link,$(STAGING_DIR)/usr/lib -laudiowrt-player -lpthread
endef

define Package/audiowrt-player-lpcm/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-lpcm $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/share/audiowrt/players
	$(INSTALL_DATA) ./files/lpcm.manifest $(1)/usr/share/audiowrt/players/lpcm.manifest
endef

define Package/audiowrt-player-lpcm/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-playback-registry rebuild
endef

define Package/audiowrt-player-lpcm/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-playback-registry exclude lpcm
endef

$(eval $(call BuildPackage,audiowrt-player-lpcm))
