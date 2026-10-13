include $(TOPDIR)/rules.mk

PKG_NAME:=kmod-bluetooth-tailored
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

# Package already-built, checksum-verified official kernel objects. Unlike
# KernelPackage, this recipe never invokes the SDK kernel build system.
PKG_VERSION:=$(LINUX_VERSION)
PKG_BUILD_DEPENDS:=
PKG_BUILD_PARALLEL:=1

define Package/kmod-bluetooth-tailored
  SECTION:=kernel
  CATEGORY:=Kernel modules
  SUBMENU:=Bluetooth Support
  TITLE:=Tailored official Bluetooth core and USB HCI modules
  PROVIDES:=kmod-bluetooth kmod-btusb kmod-btmtk
  DEPENDS:=+kernel +kmod-usb-core +kmod-crypto-hash +kmod-crypto-ec\
    +kmod-lib-crc16 +kmod-crypto-cmac +kmod-regmap-core +kmod-crypto-ecdh
endef

define Package/kmod-bluetooth-tailored/description
 Repackage the exact-release OpenWrt kernel modules for Bluetooth A2DP,
 omitting RFCOMM, BNEP and HIDP without rebuilding any kernel source.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./files/*.ko $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/kmod-bluetooth-tailored/install
	$(INSTALL_DIR) $(1)/lib/modules/$(LINUX_VERSION) $(1)/etc/modules.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/*.ko $(1)/lib/modules/$(LINUX_VERSION)/
	printf '%s\n' bluetooth btmtk btintel btrtl btusb >$(1)/etc/modules.d/40-bluetooth-tailored
endef

$(eval $(call BuildPackage,kmod-bluetooth-tailored))
