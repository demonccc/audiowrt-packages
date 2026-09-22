include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-kmod-usb-audio
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

# See audiowrt-kmod-sound-core: the final APK provides the official capability,
# while DUMP metadata stays single-owner and cycle-free.
ifneq ($(DUMP),1)
AUDIOWRT_USB_AUDIO_PROVIDES:=kmod-usb-audio
endif

define KernelPackage/audiowrt-usb-audio
  SUBMENU:=USB Support
  TITLE:=AudioWRT USB Audio Class kernel support
  PROVIDES:=$(AUDIOWRT_USB_AUDIO_PROVIDES)
  DEPENDS:=@USB_SUPPORT +kmod-usb-core +kmod-audiowrt-sound-core \
	+kmod-media-controller +kmod-sound-midi2
  KCONFIG:=CONFIG_SND_USB=y CONFIG_SND_USB_AUDIO=m
  FILES:= \
	$(PKG_BUILD_DIR)/snd-usbmidi-lib.ko \
	$(PKG_BUILD_DIR)/snd-usb-audio.ko
  AUTOLOAD:=$(call AutoProbe,snd-usbmidi-lib snd-usb-audio)
endef

define KernelPackage/audiowrt-usb-audio/description
 Repackages the exact-release USB Audio Class modules and binds them to the
 trimmed AudioWRT sound core. Playback compatibility is preserved; dependencies
 embedded in the release module remain explicit runtime requirements.
endef

# Model cross-package module ownership for the package metadata checker. The
# runtime packages above still install every module listed here.
define Package/kmod-audiowrt-usb-audio/extra_provides
	printf '%s\n' mc.ko usbcore.ko soundcore.ko snd.ko snd-hwdep.ko \
		snd-seq-device.ko snd-rawmidi.ko snd-timer.ko snd-pcm.ko \
		snd-ump.ko input-core.ko
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./files/*.ko $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
endef

$(eval $(call KernelPackage,audiowrt-usb-audio))
