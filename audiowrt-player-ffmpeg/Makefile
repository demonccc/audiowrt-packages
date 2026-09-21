include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-ffmpeg
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-ffmpeg
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT FFmpeg compatibility player
  DEPENDS:=+libaudiowrt-player +ffmpeg
endef

define Package/audiowrt-player-ffmpeg/description
 Compatibility player for container/codec combinations that need FFmpeg,
 notably WMA and ALAC. It also registers as a fallback for M4A so ALAC-in-M4A
 can play when the smaller native FAAD path rejects the stream.
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
		-o $(PKG_BUILD_DIR)/audiowrt-player-ffmpeg \
		$(PKG_BUILD_DIR)/audiowrt-player-ffmpeg.c \
		$(TARGET_LDFLAGS) -Wl,-rpath-link,$(STAGING_DIR)/usr/lib -laudiowrt-player
endef

define Package/audiowrt-player-ffmpeg/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-ffmpeg $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/ffmpeg.defaults $(1)/etc/uci-defaults/75-audiowrt-player-ffmpeg
endef

define Package/audiowrt-player-ffmpeg/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-player-registry register alac ffmpeg_audio 'AudioWRT FFmpeg Audio Player' /usr/bin/audiowrt-player-ffmpeg 'audio/alac audio/x-alac' 'alac' >/dev/null 2>&1 || true
/usr/libexec/audiowrt-player-registry register wma ffmpeg_audio 'AudioWRT FFmpeg Audio Player' /usr/bin/audiowrt-player-ffmpeg 'audio/x-ms-wma audio/wma' 'wma' >/dev/null 2>&1 || true
/usr/libexec/audiowrt-player-registry register m4a ffmpeg_audio 'AudioWRT FFmpeg Audio Player' /usr/bin/audiowrt-player-ffmpeg 'audio/mp4 audio/x-m4a audio/m4a' 'm4a mp4' >/dev/null 2>&1 || true
exit 0
endef

define Package/audiowrt-player-ffmpeg/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-player-registry unregister ffmpeg_audio >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,audiowrt-player-ffmpeg))
