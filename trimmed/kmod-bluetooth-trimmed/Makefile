include $(TOPDIR)/rules.mk

PKG_NAME:=kmod-bluetooth-trimmed
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

ifneq ($(DUMP),1)
AUDIOWRT_BLUETOOTH_PROVIDES:=kmod-bluetooth kmod-btusb kmod-btmtk
endif

define KernelPackage/bluetooth-trimmed
  SUBMENU:=Bluetooth Support
  TITLE:=Trimmed Bluetooth core and USB HCI support
  PROVIDES:=$(AUDIOWRT_BLUETOOTH_PROVIDES)
  DEPENDS:=@USB_SUPPORT +kmod-usb-core +kmod-crypto-hash +kmod-crypto-ecb \
	+kmod-lib-crc16 +kmod-crypto-cmac +kmod-regmap-core +kmod-crypto-ecdh \
	+USE_RFKILL:kmod-rfkill
  KCONFIG:=CONFIG_BT=m CONFIG_BT_BREDR=y CONFIG_BT_LE=y \
	CONFIG_BT_RFCOMM=n CONFIG_BT_BNEP=n CONFIG_BT_HIDP=n \
	CONFIG_BT_HCIBTUSB=m CONFIG_BT_HCIBTUSB_BCM=n \
	CONFIG_BT_HCIBTUSB_MTK=y CONFIG_BT_HCIBTUSB_RTL=y CONFIG_BT_MTK=m
  FILES:= \
	$(PKG_BUILD_DIR)/bluetooth.ko \
	$(PKG_BUILD_DIR)/btmtk.ko \
	$(PKG_BUILD_DIR)/btintel.ko \
	$(PKG_BUILD_DIR)/btrtl.ko \
	$(PKG_BUILD_DIR)/btusb.ko
  AUTOLOAD:=$(call AutoProbe,bluetooth btmtk btintel btrtl btusb)
endef

define KernelPackage/bluetooth-trimmed/description
 Repackages the exact-release OpenWrt Bluetooth core and USB HCI modules used
 by the constrained Bluetooth profile. RFCOMM, BNEP and HIDP are omitted; A2DP
 uses the retained Bluetooth core and HCI transport.
endef

define Package/kmod-bluetooth-trimmed/extra_provides
	printf '%s\n' crc16.ko ecdh_generic.ko kpp.ko usbcore.ko
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./files/*.ko $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
endef

$(eval $(call KernelPackage,bluetooth-trimmed))
