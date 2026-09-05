include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-mpd
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-mpd
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT MPD integration
  DEPENDS:=+audiowrt-core +mpd
endef

define Package/audiowrt-mpd/description
 Meta-package for Music Player Daemon integration on AudioWRT.
endef

define Package/audiowrt-mpd/install
	true
endef

$(eval $(call BuildPackage,audiowrt-mpd))
