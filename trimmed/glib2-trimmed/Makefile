include $(TOPDIR)/rules.mk

PKG_NAME:=glib2-trimmed
AUDIOWRT_REPACKAGE_VERSION_SOURCE:=$(TOPDIR)/feeds/packages/libs/glib2/Makefile
PKG_VERSION:=$(shell sed -n 's/^PKG_VERSION:=//p' $(AUDIOWRT_REPACKAGE_VERSION_SOURCE) 2>/dev/null | head -n1)
PKG_RELEASE:=1
PKG_LICENSE:=LGPL-2.1-or-later
PKG_MAINTAINER:=AudioWRT

ifeq ($(strip $(PKG_VERSION)),)
  $(error AudioWRT requires the selected OpenWrt packages-feed GLib2 recipe at $(AUDIOWRT_REPACKAGE_VERSION_SOURCE))
endif

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/nls.mk

define Package/glib2-trimmed
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=Trimmed GLib 2.0 runtime
  DEPENDS:=$(ICONV_DEPENDS) $(INTL_DEPENDS) +zlib +libpthread +libffi +libattr +libpcre2
  PROVIDES:=glib2
  CONFLICTS:=glib2
  URL:=https://www.gtk.org/
endef

define Package/glib2-trimmed/description
 Repackages the exact official OpenWrt GLib2 APK selected for the current
 release and architecture. It keeps the GLib, GObject, GModule and GIO runtime
 libraries required by AudioWRT Bluetooth components while omitting the unused
 GIRepository and legacy GThread shared libraries.
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

define Package/glib2-trimmed/install
	$(CP) $(PKG_BUILD_DIR)/root/. $(1)/
endef

$(eval $(call BuildPackage,glib2-trimmed))
