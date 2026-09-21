include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-aac
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-aac
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native AAC player
  DEPENDS:=+libaudiowrt-player +libfaad2 +libpthread
endef

define Package/audiowrt-player-aac/description
 Native AudioWRT ADTS/ADIF AAC player. MP4/M4A container demuxing is not
 advertised by this package.
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
		-o $(PKG_BUILD_DIR)/audiowrt-player-aac \
		$(PKG_BUILD_DIR)/audiowrt-player-aac.c \
		$(TARGET_LDFLAGS) -Wl,-rpath-link,$(STAGING_DIR)/usr/lib -laudiowrt-player -lfaad -lpthread
endef

define Package/audiowrt-player-aac/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-aac $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/aac.defaults $(1)/etc/uci-defaults/70-audiowrt-player-aac
endef

define Package/audiowrt-player-aac/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-player-registry register aac native_aac 'AudioWRT AAC Player' /usr/bin/audiowrt-player-aac 'audio/aac audio/aacp' 'aac' >/dev/null 2>&1 || true
exit 0
endef

define Package/audiowrt-player-aac/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/libexec/audiowrt-player-registry unregister native_aac >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,audiowrt-player-aac))
