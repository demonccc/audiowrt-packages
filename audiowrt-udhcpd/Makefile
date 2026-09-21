include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-udhcpd
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-udhcpd
  SECTION:=net
  CATEGORY:=Network
  TITLE:=AudioWRT minimal BusyBox DHCP server
  URL:=https://busybox.net/
  DEPENDS:=+audiowrt-busybox
endef

define Package/audiowrt-udhcpd/description
 Configuration and service wrapper for the udhcpd applet provided by
 audiowrt-busybox. It is used only for the AudioWRT provisioning AP.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-udhcpd/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/udhcpd.init $(1)/etc/init.d/audiowrt-udhcpd
endef

$(eval $(call BuildPackage,audiowrt-udhcpd))
