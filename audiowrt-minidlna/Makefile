# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

AUDIOWRT_DERIVED_NAME:=audiowrt-minidlna
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/packages/multimedia/minidlna/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk

PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/nls.mk

define Package/audiowrt-minidlna
  SECTION:=multimedia
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT audio-only DLNA server
  URL:=https://sourceforge.net/projects/minidlna/
  DEPENDS:=+libpthread +libexif +libjpeg +libsqlite3 +libffmpeg +libid3tag +libflac +libvorbis $(ICONV_DEPENDS)
  USERID:=minidlna:minidlna
  PROVIDES:=minidlna
  CONFLICTS:=minidlna
endef

define Package/audiowrt-minidlna/description
 ReadyMedia/MiniDLNA derived from the selected OpenWrt packages feed. AudioWRT
 keeps an audio-only runtime configuration and disables NLS while inheriting
 the release's exact source version, files and complete OpenWrt patch set.
endef

define Package/audiowrt-minidlna/conffiles
/etc/config/minidlna
endef

CONFIGURE_ARGS += \
	--disable-nls \
	--with-libiconv-prefix="$(ICONV_PREFIX)" \
	--with-os-name="AudioWRT" \
	--with-os-version="$(LINUX_VERSION)" \
	--with-os-url="https://github.com/demonccc/audiowrt" \
	--with-db-path="/var/run/minidlna" \
	--with-log-path="/var/log"

define Package/audiowrt-minidlna/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/sbin/minidlnad $(1)/usr/sbin/minidlnad
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(AUDIOWRT_DERIVED_FILES_DIR)/minidlna.init $(1)/etc/init.d/minidlna
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(AUDIOWRT_DERIVED_FILES_DIR)/minidlna.config $(1)/etc/config/minidlna
endef

$(eval $(call BuildPackage,audiowrt-minidlna))
