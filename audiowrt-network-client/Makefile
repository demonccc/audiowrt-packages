include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-network-client
PKG_VERSION:=1.0.1
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-network-client
  SECTION:=net
  CATEGORY:=Network
  TITLE:=AudioWRT network client manager
  DEPENDS:=+audiowrt-config +uci +ubus +netifd +jsonfilter
endef

define Package/audiowrt-network-client/description
 Common AudioWRT network client status and Ethernet configuration manager.
 It exposes runtime link, address, route and traffic information and allows
 explicit DHCP or static IPv4 configuration of the LAN client interface.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-network-client/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/audiowrt-network-client $(1)/usr/sbin/audiowrt-network-client
endef

$(eval $(call BuildPackage,audiowrt-network-client))
