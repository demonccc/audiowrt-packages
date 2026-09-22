include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-core
PKG_VERSION:=1.0.2
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-core
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT distribution package marker
  DEPENDS:=+uci +audiowrt-audio
endef

define Package/audiowrt-core/description
 AudioWRT package marker for distribution dependencies. Runtime provisioning
 state and constants are owned by the provisioning and Wi-Fi packages and are
 not stored in a persistent audiowrt UCI section.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-core/install
endef

$(eval $(call BuildPackage,audiowrt-core))
