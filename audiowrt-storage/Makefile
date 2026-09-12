include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-storage
PKG_RELEASE:=3
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-storage
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT guided extension storage
  DEPENDS:=+audiowrt-core +block-mount +kmod-usb-storage +kmod-fs-ext4 +e2fsprogs
endef

define Package/audiowrt-storage/description
 AudioWRT-only guided USB extroot manager for constrained devices. Existing OpenWrt installations should use their normal storage configuration instead.
endef

define Package/audiowrt-storage/conffiles
/etc/config/audiowrt-storage
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-storage/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/audiowrt-storage $(1)/usr/sbin/audiowrt-storage
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt-storage.config $(1)/etc/config/audiowrt-storage
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/audiowrt-storage.defaults $(1)/etc/uci-defaults/40-audiowrt-storage
endef

$(eval $(call BuildPackage,audiowrt-storage))
