include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-mdns
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-mdns
  SECTION:=net
  CATEGORY:=Network
  TITLE:=AudioWRT tiny mDNS responder
  PROVIDES:=umdns
  CONFLICTS:=umdns audiowrt-umdns
endef

define Package/audiowrt-mdns/description
 Tiny authoritative mDNS responder for constrained AudioWRT images. It only
 publishes this device hostname and the optional LuCI HTTP service; it does not
 implement mDNS browsing, caching, reflection, ubus integration or a general
 DNS-SD registry.
endef

define Package/audiowrt-mdns/conffiles
/etc/config/audiowrt-mdns
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) \
		-Wall -Wextra \
		-o $(PKG_BUILD_DIR)/audiowrt-mdns \
		$(PKG_BUILD_DIR)/audiowrt-mdns.c \
		$(TARGET_LDFLAGS)
endef

define Package/audiowrt-mdns/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-mdns $(1)/usr/sbin/audiowrt-mdns
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/audiowrt-mdns.init $(1)/etc/init.d/audiowrt-mdns
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/audiowrt-mdns.config $(1)/etc/config/audiowrt-mdns
endef

$(eval $(call BuildPackage,audiowrt-mdns))
