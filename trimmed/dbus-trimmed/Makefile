include $(TOPDIR)/rules.mk

PKG_NAME:=dbus-trimmed
AUDIOWRT_REPACKAGE_VERSION_SOURCE:=$(TOPDIR)/feeds/packages/utils/dbus/Makefile
PKG_VERSION:=$(shell sed -n 's/^PKG_VERSION:=//p' $(AUDIOWRT_REPACKAGE_VERSION_SOURCE) 2>/dev/null | head -n1)
PKG_RELEASE:=1
PKG_LICENSE:=AFL-2.1
PKG_MAINTAINER:=AudioWRT

ifeq ($(strip $(PKG_VERSION)),)
  $(error AudioWRT requires the selected OpenWrt packages-feed D-Bus recipe at $(AUDIOWRT_REPACKAGE_VERSION_SOURCE))
endif

include $(INCLUDE_DIR)/package.mk

define Package/dbus-trimmed
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Trimmed D-Bus system daemon package
  DEPENDS:=+libexpat +libdbus
  PROVIDES:=dbus
  CONFLICTS:=dbus
  USERID:=dbus=91:dbus=91
endef

define Package/dbus-trimmed/description
 Repackages the exact official OpenWrt D-Bus daemon APK selected for the
 current release and architecture. It keeps the system-bus daemon,
 dbus-uuidgen, service activation helper, init script and D-Bus configuration,
 while omitting the unused session-bus launch and cleanup utilities.
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	python3 $(CURDIR)/scripts/prepare.py \
		--release '$(VERSION_NUMBER)' \
		--arch '$(ARCH_PACKAGES)' \
		--apk '$(STAGING_DIR_HOST)/bin/apk' \
		--output '$(PKG_BUILD_DIR)/root'
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/dbus-trimmed/install
	$(CP) $(PKG_BUILD_DIR)/root/. $(1)/
endef

$(eval $(call BuildPackage,dbus-trimmed))
