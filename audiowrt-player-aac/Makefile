include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-player-aac
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-player-aac
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT native AAC player
  DEPENDS:=+audiowrt-player-core +libfaad2 +libpthread
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
	$(INSTALL_DIR) $(1)/usr/share/audiowrt/dlna/players
	$(INSTALL_DATA) ./files/aac.conf $(1)/usr/share/audiowrt/dlna/players/aac.conf
endef

$(eval $(call BuildPackage,audiowrt-player-aac))
