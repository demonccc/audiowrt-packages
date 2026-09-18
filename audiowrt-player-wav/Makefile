include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-wav
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-wav
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native WAV/PCM player
  DEPENDS:=+audiowrt-player-core +libpthread
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
		$(TARGET_LDFLAGS) -laudiowrt-player -lpthread
endef

define Package/audiowrt-player-wav/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-player-wav $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/share/audiowrt/dlna/players
	$(INSTALL_DATA) ./files/wav.conf $(1)/usr/share/audiowrt/dlna/players/wav.conf
endef

$(eval $(call BuildPackage,audiowrt-player-wav))
