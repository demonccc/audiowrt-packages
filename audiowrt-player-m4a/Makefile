include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-m4a
PKG_VERSION:=1.0.3
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-m4a
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT M4A/AAC player
  DEPENDS:=+libaudiowrt-player +faad2
endef

define Package/audiowrt-player-m4a/description
 AudioWRT M4A/MP4 AAC player. The DLNA object is downloaded to tmpfs so FAAD
 can seek the MP4 container, then decoded PCM is streamed directly to ALSA.
 No media or decoder cache is written to persistent storage.
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
		-o $(PKG_BUILD_DIR)/audiowrt-player-m4a \
		$(PKG_BUILD_DIR)/audiowrt-player-m4a.c \
		$(TARGET_LDFLAGS) -Wl,-rpath-link,$(STAGING_DIR)/usr/lib -laudiowrt-player
endef

define Package/audiowrt-player-m4a/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-m4a $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/share/audiowrt/players
	$(INSTALL_DATA) ./files/m4a.manifest $(1)/usr/share/audiowrt/players/m4a.manifest
endef

define Package/audiowrt-player-m4a/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-playback-registry rebuild
endef

define Package/audiowrt-player-m4a/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-playback-registry exclude m4a
endef

$(eval $(call BuildPackage,audiowrt-player-m4a))
