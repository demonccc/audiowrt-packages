include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-bluez
PKG_VERSION:=5.83
PKG_RELEASE:=5

PKG_SOURCE:=bluez-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=@KERNEL/linux/bluetooth/
PKG_HASH:=108522d909d220581399bfec93daab62035539ceef3dda3e79970785c63bd24c
PKG_BUILD_DIR:=$(BUILD_DIR)/bluez-$(PKG_VERSION)

PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=COPYING
PKG_MAINTAINER:=AudioWRT
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=gc-sections

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-bluez-libs
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=AudioWRT minimal BlueZ library
  DEPENDS:=+libpthread
  URL:=https://www.bluez.org/
endef

define Package/audiowrt-bluez-libs/description
 Minimal libbluetooth runtime built together with the AudioWRT BlueZ daemon.
endef

define Package/audiowrt-bluez
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=AudioWRT minimal BlueZ audio/MIDI daemon
  DEPENDS:=+audiowrt-bluez-libs +glib2 +dbus +alsa-lib
  URL:=https://www.bluez.org/
endef

define Package/audiowrt-bluez/description
 Minimal BlueZ daemon for AudioWRT A2DP Source output and Bluetooth MIDI via
 ALSA Sequencer. MIDI is included in the current 8 MB measurement; bluetoothctl,
 OBEX, generic command-line tools, monitor/debug tooling and unrelated Bluetooth
 profiles remain omitted.
endef

define Package/audiowrt-bluez/conffiles
/etc/bluetooth/main.conf
endef

# Keep bluetoothd, libbluetooth, classic A2DP/AVRCP and Bluetooth MIDI. AudioWRT
# owns discovery/pair/connect UX through its compact D-Bus helper. Other modern
# LE Audio profiles remain disabled until AudioWRT has a product use for them.
#
# Build the static libbluetooth archive as a development/staging artifact because
# Build/InstallDev mirrors OpenWrt's BlueZ package and stages libbluetooth.a along
# with the shared library. The static archive is not installed in the firmware.
CONFIGURE_ARGS += \
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
	--enable-midi \
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

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_INSTALL_DIR)/usr/include/bluetooth $(1)/usr/include/
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libbluetooth.{a,so*} $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/lib/pkgconfig
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/bluez.pc $(1)/usr/lib/pkgconfig/
endef

define Package/audiowrt-bluez-libs/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libbluetooth.so.* $(1)/usr/lib/
endef

define Package/audiowrt-bluez/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/lib/bluetooth/bluetoothd $(1)/usr/sbin/bluetoothd
	$(INSTALL_DIR) $(1)/etc/dbus-1/system.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/bluetooth.conf $(1)/etc/dbus-1/system.d/bluetooth.conf
	$(INSTALL_DIR) $(1)/etc/bluetooth
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/main.conf $(1)/etc/bluetooth/main.conf
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/bluetoothd.init $(1)/etc/init.d/bluetoothd
endef

$(eval $(call BuildPackage,audiowrt-bluez-libs))
$(eval $(call BuildPackage,audiowrt-bluez))
