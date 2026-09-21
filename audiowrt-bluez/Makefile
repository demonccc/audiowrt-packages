include $(TOPDIR)/rules.mk

AUDIOWRT_DERIVED_NAME:=audiowrt-bluez
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/packages/utils/bluez/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk

PKG_MAINTAINER:=AudioWRT
PKG_RELEASE:=3

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-bluez
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=AudioWRT minimal BlueZ audio daemon
  DEPENDS:=+bluez-libs +glib2 +dbus
  URL:=https://www.bluez.org/
endef

define Package/audiowrt-bluez/description
 Minimal BlueZ daemon for AudioWRT A2DP Source output. The source version and
 all OpenWrt patches come from the selected release; AudioWRT only applies the
 profile/feature delta needed for audio output.
endef

define Package/audiowrt-bluez/conffiles
/etc/bluetooth/main.conf
endef

CONFIGURE_ARGS += \
	--localstatedir=/tmp \
	--disable-android \
	--disable-asha \
	--disable-bap \
	--disable-bass \
	--disable-btpclient \
	--disable-ccp \
	--disable-client \
	--disable-csip \
	--disable-cups \
	--disable-datafiles \
	--disable-deprecated \
	--disable-experimental \
	--disable-health \
	--disable-hid \
	--disable-hog \
	--enable-library \
	--enable-static \
	--disable-manpages \
	--disable-mcp \
	--disable-mesh \
	--disable-micp \
	--disable-midi \
	--disable-monitor \
	--disable-network \
	--disable-nfc \
	--disable-obex \
	--disable-sap \
	--disable-sixaxis \
	--disable-systemd \
	--disable-test \
	--disable-testing \
	--disable-tools \
	--disable-udev \
	--disable-vcp \
	--enable-threads

define Package/audiowrt-bluez/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/lib/bluetooth/bluetoothd $(1)/usr/sbin/bluetoothd
	$(INSTALL_DIR) $(1)/etc/dbus-1/system.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/bluetooth.conf $(1)/etc/dbus-1/system.d/bluetooth.conf
	$(INSTALL_DIR) $(1)/etc/bluetooth
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/main.conf $(1)/etc/bluetooth/main.conf
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(AUDIOWRT_DERIVED_FILES_DIR)/bluetoothd.init $(1)/etc/init.d/bluetoothd
endef

$(eval $(call BuildPackage,audiowrt-bluez))
