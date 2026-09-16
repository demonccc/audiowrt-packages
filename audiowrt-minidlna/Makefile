# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=minidlna
PKG_VERSION:=1.3.3
PKG_RELEASE:=101

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=@SF/minidlna
PKG_HASH:=39026c6d4a139b9180192d1c37225aa3376fdf4f1a74d7debbdbb693d996afa4

PKG_MAINTAINER:=AudioWRT
PKG_LICENSE:=GPL-2.0-or-later BSD-3-Clause
PKG_LICENSE_FILES:=COPYING LICENCE.miniupnpd
PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=gc-sections lto

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
 ReadyMedia/MiniDLNA packaged for AudioWRT. Runtime configuration exposes only
 audio media directories and disables unrelated presentation features. NLS is
 disabled to keep the constrained-device package smaller.
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
	$(INSTALL_BIN) ./files/minidlna.init $(1)/etc/init.d/minidlna
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/minidlna.config $(1)/etc/config/minidlna
endef

$(eval $(call BuildPackage,audiowrt-minidlna))
