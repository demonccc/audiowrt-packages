include $(TOPDIR)/rules.mk

PKG_NAME:=alsa-lib
PKG_VERSION:=1.2.11
PKG_RELEASE:=100

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.bz2
PKG_SOURCE_URL:=https://www.alsa-project.org/files/pub/lib/ \
		https://distfiles.gentoo.org/distfiles/
PKG_HASH:=9f3f2f69b995f9ad37359072fbc69a3a88bfba081fc83e9be30e14662795bb4d

PKG_MAINTAINER:=AudioWRT
PKG_LICENSE:=LGPL-2.1-or-later
PKG_LICENSE_FILES:=COPYING
PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16 no-lto gc-sections

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-minimal-alsa
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=AudioWRT minimal ALSA library
  URL:=https://www.alsa-project.org/
  DEPENDS:=@AUDIO_SUPPORT +kmod-sound-core +libpthread +librt
  PROVIDES:=alsa-lib
  CONFLICTS:=alsa-lib
endef

define Package/audiowrt-minimal-alsa/description
 ALSA userspace trimmed for AudioWRT. It retains PCM and mixer/control plus the
 hw, plug, rate, route and dmix paths used by USB Audio and BlueALSA. MIDI,
 Sequencer, topology, UCM and unrelated plugins are omitted.
endef

define Package/audiowrt-minimal-alsa/conffiles
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
	--with-pcm-plugins=linear,route,rate,plug,dmix \
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

define Package/audiowrt-minimal-alsa/install
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

$(eval $(call BuildPackage,audiowrt-minimal-alsa))
