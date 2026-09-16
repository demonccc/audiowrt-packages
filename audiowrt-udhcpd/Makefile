include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-udhcpd
PKG_VERSION:=1.37.0
PKG_RELEASE:=1
PKG_SOURCE:=busybox-$(PKG_VERSION).tar.bz2
PKG_SOURCE_URL:=https://www.busybox.net/downloads \
	 https://sources.buildroot.net/busybox
PKG_HASH:=3311dff32e746499f4df0d5df04d7eb396382d7e108bb9250e7b519b837043a4
PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-udhcpd
  SECTION:=net
  CATEGORY:=Network
  TITLE:=AudioWRT minimal BusyBox DHCP server
  URL:=https://busybox.net/
  DEPENDS:=+libc
endef

define Package/audiowrt-udhcpd/description
 Standalone BusyBox udhcpd binary used only for the AudioWRT provisioning AP.
 It avoids installing the full OpenWrt DHCP/DNS daemon stack.
endef

define Build/Configure
	rm -f $(PKG_BUILD_DIR)/.config
	touch $(PKG_BUILD_DIR)/.config
	cat ./files/busybox.config >> $(PKG_BUILD_DIR)/.config
	yes n | $(MAKE) -C $(PKG_BUILD_DIR) $(TARGET_CONFIGURE_OPTS) oldconfig
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) $(TARGET_CONFIGURE_OPTS) \
		EXTRA_CFLAGS="$(TARGET_CFLAGS)" \
		EXTRA_LDFLAGS="$(TARGET_LDFLAGS)" \
		CONFIG_PREFIX="$(PKG_INSTALL_DIR)" busybox
endef

define Package/audiowrt-udhcpd/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/busybox $(1)/usr/sbin/udhcpd
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/udhcpd.init $(1)/etc/init.d/audiowrt-udhcpd
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_CONF) ./files/udhcpd.conf $(1)/etc/udhcpd.conf
endef

$(eval $(call BuildPackage,audiowrt-udhcpd))
