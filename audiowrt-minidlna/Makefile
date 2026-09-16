# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-minidlna
PKG_RELEASE:=2
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-minidlna
  SECTION:=multimedia
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT audio-only MiniDLNA profile
  DEPENDS:=+minidlna
endef

define Package/audiowrt-minidlna/description
 AudioWRT runtime profile for the exact MiniDLNA binary shipped by the selected
 OpenWrt release. The official binary already contains that release's source,
 patches and architecture-specific build. AudioWRT only applies the audio-only
 runtime configuration and never rebuilds MiniDLNA or its FFmpeg dependency
 graph in a selective SDK build.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/audiowrt-minidlna/install
	$(INSTALL_DIR) $(1)/usr/share/audiowrt
	$(INSTALL_DATA) ./files/minidlna.config $(1)/usr/share/audiowrt/minidlna.config
endef

define Package/audiowrt-minidlna/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || exit 0
[ -f "$${IPKG_INSTROOT}/usr/share/audiowrt/minidlna.config" ] || exit 0
cp "$${IPKG_INSTROOT}/usr/share/audiowrt/minidlna.config" "$${IPKG_INSTROOT}/etc/config/minidlna"
endef

$(eval $(call BuildPackage,audiowrt-minidlna))
