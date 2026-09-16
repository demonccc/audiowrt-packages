include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-udhcpd
PKG_VERSION:=1
PKG_RELEASE:=1
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-udhcpd
  SECTION:=net
  CATEGORY:=Network
  TITLE:=AudioWRT minimal BusyBox DHCP server
  URL:=https://busybox.net/
  DEPENDS:=+busybox
endef

define Package/audiowrt-udhcpd/description
 Configuration and service wrapper for the udhcpd applet in OpenWrt's
 standard BusyBox binary. It is used only for the AudioWRT provisioning AP.
endef

define Package/audiowrt-udhcpd/install
	$(INSTALL_DIR) $(1)/usr/sbin
	ln -sf /bin/busybox $(1)/usr/sbin/udhcpd
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/udhcpd.init $(1)/etc/init.d/audiowrt-udhcpd
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_CONF) ./files/udhcpd.conf $(1)/etc/udhcpd.conf
endef

$(eval $(call BuildPackage,audiowrt-udhcpd))
