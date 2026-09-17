# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-minimal-dlna-renderer
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-minimal-dlna-renderer
  SECTION:=sound
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT minimal UPnP/DLNA audio renderer
  DEPENDS:=+libpthread +libupnp +libflac +libmad +alsa-lib
endef

define Package/audiowrt-minimal-dlna-renderer/description
 Compact AudioWRT-owned UPnP AV MediaRenderer for constrained devices. It
 accepts HTTP FLAC and MP3 resources and decodes directly to ALSA, avoiding
 MPD, upmpdcli, FFmpeg and general-purpose media frameworks.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) \
		-ffunction-sections -fdata-sections \
		-o $(PKG_BUILD_DIR)/audiowrt-dlna-renderer \
		$(PKG_BUILD_DIR)/audiowrt-dlna-renderer.c \
		$(TARGET_LDFLAGS) -Wl,--gc-sections \
		-lupnp -lixml -lFLAC -lmad -lasound -lpthread -lm
endef

define Package/audiowrt-minimal-dlna-renderer/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/audiowrt-dlna-renderer $(1)/usr/sbin/

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/audiowrt-dlna-renderer.init $(1)/etc/init.d/audiowrt-dlna-renderer

	$(INSTALL_DIR) $(1)/usr/share/audiowrt-dlna
	$(INSTALL_DATA) ./files/description.xml.in $(1)/usr/share/audiowrt-dlna/
	$(INSTALL_DATA) ./files/AVTransport.xml $(1)/usr/share/audiowrt-dlna/
	$(INSTALL_DATA) ./files/RenderingControl.xml $(1)/usr/share/audiowrt-dlna/
	$(INSTALL_DATA) ./files/ConnectionManager.xml $(1)/usr/share/audiowrt-dlna/
endef

$(eval $(call BuildPackage,audiowrt-minimal-dlna-renderer))
