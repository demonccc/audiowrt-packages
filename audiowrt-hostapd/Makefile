include $(TOPDIR)/rules.mk

AUDIOWRT_DERIVED_NAME:=audiowrt-hostapd
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/base/network/services/hostapd/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk

PKG_MAINTAINER:=AudioWRT
PKG_RELEASE:=1
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=gc-sections lto

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	$(Build/Prepare/AudioWRTDerived)
endef

define Package/audiowrt-hostapd
  SECTION:=net
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT minimal open provisioning AP
  URL:=https://w1.fi/hostapd/
  DEPENDS:=+libnl-tiny +hostapd-common +libubox +ucode +libucode +ucode-mod-fs +ucode-mod-nl80211 +ucode-mod-rtnl +ucode-mod-ubus +ucode-mod-uloop +libubus +libblobmsg-json +libudebug
  PROVIDES:=hostapd
  USERID:=network=101:network=101
endef

define Package/audiowrt-hostapd/description
 Open-AP-only hostapd derived from the selected OpenWrt release for AudioWRT
 provisioning. It keeps nl80211, OpenWrt UBus/UCode integration, the global
 control socket and syslog support while omitting WPA, EAP, RADIUS, WPS,
 VLAN, wired-authenticator and other features unnecessary for the temporary
 unencrypted setup network.
endef

TARGET_CPPFLAGS := \
	-I$(STAGING_DIR)/usr/include/libnl-tiny \
	-I$(PKG_BUILD_DIR)/src/crypto \
	$(TARGET_CPPFLAGS) \
	-DCONFIG_LIBNL20 \
	-D_GNU_SOURCE \
	-DCONFIG_MSG_MIN_PRIORITY=3

TARGET_LDFLAGS += \
	-lubox -lubus -lblobmsg_json -lucode -lm -lnl-tiny -ludebug

define Build/Configure
	$(CP) ./files/hostapd-audiowrt.config $(PKG_BUILD_DIR)/hostapd/.config
endef

define Build/Compile
	+CFLAGS="$(TARGET_CPPFLAGS) $(TARGET_CFLAGS)" \
	$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR)/hostapd \
		$(TARGET_CONFIGURE_OPTS) \
		CONFIG_DRIVER_NL80211=y \
		CONFIG_UCODE=y \
		CONFIG_APUP=y \
		LIBS="$(TARGET_LDFLAGS)" \
		AR="$(TARGET_CROSS)gcc-ar" \
		BCHECK= \
		hostapd
endef

define Package/audiowrt-hostapd/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/share/hostap
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/hostapd/hostapd $(1)/usr/sbin/
	$(INSTALL_DATA) $(AUDIOWRT_DERIVED_FILES_DIR)/hostapd.uc $(1)/usr/share/hostap/
endef

$(eval $(call BuildPackage,audiowrt-hostapd))
