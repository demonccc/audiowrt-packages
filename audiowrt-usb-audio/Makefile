include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-usb-audio
PKG_RELEASE:=3
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-usb-audio
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT USB audio output manager
  DEPENDS:=+audiowrt-core +kmod-usb-audio +alsa-lib
endef

define Package/audiowrt-usb-audio/description
 USB Audio Class support plus automatic ALSA default-device selection for AudioWRT.
endef

define Package/audiowrt-usb-audio/install
	$(INSTALL_DIR) $(1)/usr/libexec/audiowrt
	$(INSTALL_BIN) ./files/select-audio-output $(1)/usr/libexec/audiowrt/select-audio-output

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/audiowrt-audio.init $(1)/etc/init.d/audiowrt-audio

	$(INSTALL_DIR) $(1)/etc/hotplug.d/usb
	$(INSTALL_BIN) ./files/audiowrt-audio.hotplug $(1)/etc/hotplug.d/usb/90-audiowrt-audio
endef

$(eval $(call BuildPackage,audiowrt-usb-audio))
