include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-kmod-sound-core
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

# The profile selects this package explicitly. Keep the replacement contract
# in the generated APK, but hide it while OpenWrt generates Kconfig to avoid a
# provider cycle with the official kmod-sound-core package.
ifneq ($(DUMP),1)
AUDIOWRT_SOUND_CORE_PROVIDES:=kmod-sound-core
endif

define KernelPackage/audiowrt-sound-core
  SUBMENU:=Sound Support
  TITLE:=AudioWRT minimal ALSA kernel core
  PROVIDES:=$(AUDIOWRT_SOUND_CORE_PROVIDES)
  DEPENDS:=@AUDIO_SUPPORT +kmod-input-core
  KCONFIG:=CONFIG_SOUND=m CONFIG_SND=m CONFIG_SND_HWDEP=m \
	CONFIG_SND_RAWMIDI=m CONFIG_SND_SEQ_DEVICE=m CONFIG_SND_TIMER=m \
	CONFIG_SND_PCM=m CONFIG_SND_PCM_TIMER=y \
	CONFIG_SND_PCM_OSS=n CONFIG_SND_MIXER_OSS=n \
	CONFIG_SND_COMPRESS_OFFLOAD=n
  FILES:= \
	$(PKG_BUILD_DIR)/soundcore.ko \
	$(PKG_BUILD_DIR)/snd.ko \
	$(PKG_BUILD_DIR)/snd-hwdep.ko \
	$(PKG_BUILD_DIR)/snd-seq-device.ko \
	$(PKG_BUILD_DIR)/snd-rawmidi.ko \
	$(PKG_BUILD_DIR)/snd-timer.ko \
	$(PKG_BUILD_DIR)/snd-pcm.ko
  AUTOLOAD:=$(call AutoLoad,30,soundcore snd snd-hwdep snd-seq-device snd-rawmidi snd-timer snd-pcm)
endef

define KernelPackage/audiowrt-sound-core/description
 Repackages the exact-release ALSA kernel core required by USB Audio. OSS PCM,
 OSS mixer and compressed-offload modules are omitted.
endef

# The exact-release input module remains an official runtime package and is
# intentionally not installed as SDK source for this NO_DEPS package build.
define Package/kmod-audiowrt-sound-core/extra_provides
	printf '%s\n' input-core.ko
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./files/*.ko $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
endef

$(eval $(call KernelPackage,audiowrt-sound-core))
