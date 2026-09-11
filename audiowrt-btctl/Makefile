include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-btctl
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-btctl
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=AudioWRT compact BlueZ D-Bus controller
  DEPENDS:=+glib2
endef

define Package/audiowrt-btctl/description
 Small AudioWRT-specific BlueZ controller for adapter power, discovery,
 pairing, trust and connection management without bluetoothctl/readline/ncurses.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) -include stdlib.h \
		-I$(STAGING_DIR)/usr/include/glib-2.0 \
		-I$(STAGING_DIR)/usr/lib/glib-2.0/include \
		-I$(STAGING_DIR)/usr/include/gio-unix-2.0 \
		-o $(PKG_BUILD_DIR)/audiowrt-btctl \
		$(PKG_BUILD_DIR)/audiowrt-btctl.c \
		$(TARGET_LDFLAGS) -lgio-2.0 -lgobject-2.0 -lglib-2.0
endef

define Package/audiowrt-btctl/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-btctl $(1)/usr/bin/audiowrt-btctl
endef

$(eval $(call BuildPackage,audiowrt-btctl))
