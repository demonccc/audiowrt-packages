# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=umdns
PKG_RELEASE:=101

PKG_SOURCE_URL:=$(PROJECT_GIT)/project/mdnsd.git
PKG_SOURCE_PROTO:=git
PKG_SOURCE_DATE:=2026-06-16
PKG_SOURCE_VERSION:=1b5e7bf1cec775b89f1a6068dc0b9df3593b5986
PKG_MIRROR_HASH:=7d9ec860af2b8217f65cd4af92a61be1925ad171dee9b536c4914cc0080e3303

PKG_MAINTAINER:=AudioWRT
PKG_LICENSE:=LGPL-2.1
PKG_BUILD_FLAGS:=gc-sections lto

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/audiowrt-umdns
  SECTION:=net
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT minimal mDNS daemon
  DEPENDS:=+libubox +libubus +libblobmsg-json +libudebug
  PROVIDES:=umdns
  CONFLICTS:=umdns
endef

define Package/audiowrt-umdns/description
 Minimal AudioWRT build of OpenWrt umdns. It keeps the daemon and UCI/procd
 integration needed for .local naming and mDNS publication while omitting the
 CLI ucode helper and seccomp profile from constrained images.
endef

define Package/audiowrt-umdns/conffiles
/etc/config/umdns
endef

TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include

define Package/audiowrt-umdns/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/umdns $(1)/usr/sbin/umdns
	$(INSTALL_BIN) ./files/umdns.init $(1)/etc/init.d/umdns
	$(INSTALL_CONF) ./files/umdns.config $(1)/etc/config/umdns
endef

$(eval $(call BuildPackage,audiowrt-umdns))
