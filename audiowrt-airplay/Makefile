include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-airplay
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-airplay
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT AirPlay integration
  DEPENDS:=+audiowrt-core +shairport-sync
endef

define Package/audiowrt-airplay/description
 Meta-package for AirPlay receiver support through Shairport Sync.
endef

define Package/audiowrt-airplay/install
	true
endef

$(eval $(call BuildPackage,audiowrt-airplay))
