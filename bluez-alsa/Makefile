include $(TOPDIR)/rules.mk

PKG_NAME:=bluez-alsa
PKG_VERSION:=4.1.1
PKG_RELEASE:=3

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/Arkq/bluez-alsa/archive/v$(PKG_VERSION)
PKG_HASH:=b69a3e6dd69315194403ee930ac1553aed3fb9a3988e502ae5c24a8bfef70f9f

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=AudioWRT
PKG_FIXUP:=autoreconf
PKG_BUILD_PARALLEL:=1
# BlueALSA's configure step requires the host-side gdbus-codegen utility.
# OpenWrt's glib2 HostBuild installs that tool into STAGING_DIR_HOSTPKG.
PKG_BUILD_DEPENDS:=glib2/host

include $(INCLUDE_DIR)/package.mk

define Package/bluez-alsa
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=BlueALSA Bluetooth audio backend
  DEPENDS:=+alsa-lib +bluez-daemon +glib2 +sbc +dbus
  URL:=https://github.com/arkq/bluez-alsa
endef

define Package/bluez-alsa/description
 Minimal BlueZ-to-ALSA bridge for AudioWRT Bluetooth A2DP Source output.
endef

# AudioWRT sends audio to Bluetooth speakers/headsets. Keep only the daemon,
# ALSA plugins and mandatory SBC codec path; receiver-side utilities and
# unrelated profiles/codecs are intentionally disabled for the 8 MB baseline.
CONFIGURE_ARGS += \
	--disable-aac \
	--disable-a2dpconf \
	--disable-aplay \
	--disable-aptx \
	--disable-aptx-hd \
	--disable-cli \
	--disable-debug \
	--disable-faststream \
	--disable-hcitop \
	--disable-lc3plus \
	--disable-ldac \
	--disable-manpages \
	--disable-mp3lame \
	--disable-mpg123 \
	--disable-msbc \
	--disable-ofono \
	--disable-rfcomm \
	--disable-systemd \
	--disable-test \
	--disable-upower

define Package/bluez-alsa/install
	$(INSTALL_DIR) $(1)/etc/alsa/conf.d
	$(CP) $(PKG_BUILD_DIR)/src/asound/20-bluealsa.conf $(1)/etc/alsa/conf.d/
	$(INSTALL_DIR) $(1)/usr/lib/alsa-lib
	$(CP) $(PKG_BUILD_DIR)/src/asound/.libs/libasound_module_*_bluealsa.so $(1)/usr/lib/alsa-lib/
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/bluealsa $(1)/usr/bin/bluealsa
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/bluealsa.init $(1)/etc/init.d/bluealsa
	$(INSTALL_DIR) $(1)/etc/dbus-1/system.d
	$(INSTALL_DATA) ./files/bluealsa.conf $(1)/etc/dbus-1/system.d/bluealsa.conf
endef

$(eval $(call BuildPackage,bluez-alsa))
