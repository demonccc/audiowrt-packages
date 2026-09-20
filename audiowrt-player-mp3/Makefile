include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-mp3
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-mp3
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native MP3 player
  DEPENDS:=+libaudiowrt-player +libmpg123 +libpthread
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
		-o $(PKG_BUILD_DIR)/audiowrt-player-mp3 \
		$(PKG_BUILD_DIR)/audiowrt-player-mp3.c \
		$(TARGET_LDFLAGS) -Wl,-rpath-link,$(STAGING_DIR)/usr/lib -laudiowrt-player -lmpg123 -lpthread
endef

define Package/audiowrt-player-mp3/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-mp3 $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/share/audiowrt/dlna/players
	$(INSTALL_DATA) ./files/mp3.conf $(1)/usr/share/audiowrt/dlna/players/mp3.conf
endef

$(eval $(call BuildPackage,audiowrt-player-mp3))
