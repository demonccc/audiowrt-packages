include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-storage
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-storage
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT extension storage manager
  DEPENDS:=+audiowrt-core +block-mount +kmod-usb-storage +kmod-fs-ext4 +e2fsprogs
endef

define Package/audiowrt-storage/description
 Manages optional external ext4 storage used to expand AudioWRT package space while preserving the internal core firmware as a boot fallback.
endef

define Package/audiowrt-storage/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/audiowrt-storage $(1)/usr/sbin/audiowrt-storage

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/audiowrt-storage.defaults $(1)/etc/uci-defaults/40-audiowrt-storage
endef

$(eval $(call BuildPackage,audiowrt-storage))
