include $(TOPDIR)/rules.mk

AUDIOWRT_DERIVED_NAME:=audiowrt-wpa-supplicant
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/base/network/services/hostapd/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk

PKG_MAINTAINER:=AudioWRT
PKG_RELEASE:=4
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=gc-sections lto

include $(INCLUDE_DIR)/package.mk


define Build/Prepare
	$(Build/Prepare/AudioWRTDerived)
endef

define Package/audiowrt-wpa-supplicant
  SECTION:=net
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT minimal WPA2/WPA3 station supplicant
  URL:=https://w1.fi/wpa_supplicant/
  DEPENDS:=+libnl-tiny +hostapd-common +libubox +ucode +libucode +ucode-mod-fs +ucode-mod-nl80211 +ucode-mod-rtnl +ucode-mod-ubus +ucode-mod-uloop +libubus +libblobmsg-json +libudebug +libmbedtls
  PROVIDES:=wpa-supplicant
  USERID:=network=101:network=101
endef

define Package/audiowrt-wpa-supplicant/description
 Client-only nl80211 WPA supplicant derived from the selected OpenWrt release.
 It keeps WPA2-PSK, WPA3-SAE, PMF/802.11w, the control interface and OpenWrt
 UBus integration while omitting EAP Enterprise, WPS, AP, mesh, P2P,
 interworking/Hotspot 2.0, FILS, IBSS and other non-AudioWRT station features.
endef

TARGET_CPPFLAGS := \
	-I$(STAGING_DIR)/usr/include/libnl-tiny \
	-I$(PKG_BUILD_DIR)/src/crypto \
	$(TARGET_CPPFLAGS) \
	-DCONFIG_LIBNL20 \
	-D_GNU_SOURCE \
	-DCONFIG_MSG_MIN_PRIORITY=3

TARGET_LDFLAGS += \
	-lubox -lubus -lblobmsg_json -lucode -lm -lnl-tiny -ludebug \
	-lmbedcrypto -lmbedx509 -lmbedtls

define Build/Configure
	$(CP) ./files/wpa_supplicant-audiowrt.config $(PKG_BUILD_DIR)/wpa_supplicant/.config
endef

define Build/Compile
	+CFLAGS="$(TARGET_CPPFLAGS) $(TARGET_CFLAGS)" \
	$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR)/wpa_supplicant \
		$(TARGET_CONFIGURE_OPTS) \
		CONFIG_DRIVER_NL80211=y \
		CONFIG_UCODE=y \
		CONFIG_TLS=mbedtls \
		CONFIG_SAE=y \
		LIBS="$(TARGET_LDFLAGS)" \
		AR="$(TARGET_CROSS)gcc-ar" \
		BCHECK= \
		wpa_supplicant
endef

define Package/audiowrt-wpa-supplicant/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/share/hostap
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/wpa_supplicant/wpa_supplicant $(1)/usr/sbin/
	$(INSTALL_DATA) $(AUDIOWRT_DERIVED_FILES_DIR)/wpa_supplicant.uc $(1)/usr/share/hostap/
endef

$(eval $(call BuildPackage,audiowrt-wpa-supplicant))
