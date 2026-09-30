include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-core
PKG_VERSION:=1.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-core
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT core runtime
  DEPENDS:=+uci +audiowrt-audio
endef

define Package/audiowrt-core/description
 AudioWRT core runtime shared by reusable AudioWRT packages. It provides the
 deterministic device identity generated from the permanent onboard MAC and
 common distribution dependency conventions. Runtime identity is kept only in
 /tmp and is independent from hostname and boot time.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-core/install
	$(INSTALL_DIR) $(1)/usr/share/audiowrt
	printf '%s\n' 'AudioWRT core runtime' > $(1)/usr/share/audiowrt/core
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/audiowrt-identity.init $(1)/etc/init.d/audiowrt-identity
endef

$(eval $(call BuildPackage,audiowrt-core))
