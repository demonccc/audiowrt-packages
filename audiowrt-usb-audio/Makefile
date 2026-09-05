include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-usb-audio
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-usb-audio
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT USB audio support
  DEPENDS:=+audiowrt-core +kmod-usb-audio +alsa-utils
endef

define Package/audiowrt-usb-audio/description
 USB Audio Class kernel support and ALSA command-line utilities for AudioWRT.
endef

define Package/audiowrt-usb-audio/install
	true
endef

$(eval $(call BuildPackage,audiowrt-usb-audio))
