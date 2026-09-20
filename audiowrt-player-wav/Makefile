include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-wav
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-wav
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native WAV/PCM player
  DEPENDS:=+libaudiowrt-player +libpthread
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
		-o $(PKG_BUILD_DIR)/audiowrt-player-wav \
		$(PKG_BUILD_DIR)/audiowrt-player-wav.c \
		$(TARGET_LDFLAGS) -Wl,-rpath-link,$(STAGING_DIR)/usr/lib -laudiowrt-player -lpthread
endef

define Package/audiowrt-player-wav/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-wav $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/wav.defaults $(1)/etc/uci-defaults/70-audiowrt-player-wav
endef

define Package/audiowrt-player-wav/postinst
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-player-registry register wav native_wav 'AudioWRT WAV/PCM Player' /usr/bin/audiowrt-player-wav 'audio/wav audio/x-wav audio/wave' 'wav' >/dev/null 2>&1 || true
exit 0
endef

define Package/audiowrt-player-wav/prerm
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-player-registry unregister native_wav >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,audiowrt-player-wav))
