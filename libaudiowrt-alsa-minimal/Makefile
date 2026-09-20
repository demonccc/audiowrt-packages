include $(TOPDIR)/rules.mk

AUDIOWRT_DERIVED_NAME:=libaudiowrt-alsa-minimal
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/packages/libs/alsa-lib/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk

PKG_MAINTAINER:=AudioWRT
PKG_RELEASE:=3

include $(INCLUDE_DIR)/package.mk

define Package/libaudiowrt-alsa-minimal
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=AudioWRT minimal ALSA library
  URL:=https://www.alsa-project.org/
  DEPENDS:=@AUDIO_SUPPORT +libpthread +librt
  PROVIDES:=alsa-lib
endef

define Package/libaudiowrt-alsa-minimal/description
 ALSA userspace derived from the selected OpenWrt release. It retains PCM and
 core PCM/control plus the hw, plug, rate, route, dmix and external PCM I/O paths
 used by USB Audio and BlueALSA. MIDI, Sequencer, topology, UCM and unrelated
 plugins are omitted.
endef

define Package/libaudiowrt-alsa-minimal/conffiles
/etc/asound.conf
endef

TARGET_CFLAGS += $(FPIC)

CONFIGURE_ARGS += \
	--disable-python \
	--disable-debug \
	--without-debug \
	--without-versioned \
	--disable-aload \
	--disable-rawmidi \
	--disable-seq \
	--disable-hwdep \
	--disable-ucm \
	--disable-topology \
	--disable-alisp \
	--disable-old-symbols \
	--with-pcm-plugins=linear,route,rate,plug,dmix,ioplug \
	--with-ctl-plugins= \
	--with-max-cards=8 \
	$(SOFT_FLOAT_CONFIG_OPTION)

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_INSTALL_DIR)/usr/include/alsa $(1)/usr/include/
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libasound.{la,so*} $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/lib/pkgconfig
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/alsa.pc $(1)/usr/lib/pkgconfig/
	$(INSTALL_DIR) $(1)/usr/share/aclocal
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/usr/share/aclocal/alsa.m4 $(1)/usr/share/aclocal/
endef

define Package/libaudiowrt-alsa-minimal/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libasound.so.* $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/share/alsa/ctl $(1)/usr/share/alsa/pcm
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/usr/share/alsa/alsa.conf $(1)/usr/share/alsa/
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/usr/share/alsa/ctl/default.conf $(1)/usr/share/alsa/ctl/
	$(INSTALL_DATA) \
		$(PKG_INSTALL_DIR)/usr/share/alsa/pcm/default.conf \
		$(PKG_INSTALL_DIR)/usr/share/alsa/pcm/dmix.conf \
		$(PKG_INSTALL_DIR)/usr/share/alsa/pcm/dsnoop.conf \
		$(1)/usr/share/alsa/pcm/
endef

$(eval $(call BuildPackage,libaudiowrt-alsa-minimal))
