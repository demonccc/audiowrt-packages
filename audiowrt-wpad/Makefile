include $(TOPDIR)/rules.mk

AUDIOWRT_DERIVED_NAME:=audiowrt-wpad
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/base/network/services/hostapd/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk

PKG_MAINTAINER:=AudioWRT
PKG_RELEASE:=3
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=gc-sections lto

include $(INCLUDE_DIR)/package.mk

# Match OpenWrt's hostapd/wpad link split: helper binaries use the base linker
# flags, while the multicall hostapd/wpa_supplicant targets receive the runtime
# libraries added below.
TARGET_LDFLAGS_C:=$(TARGET_LDFLAGS)

define Build/Prepare
	$(Build/Prepare/AudioWRTDerived)
endef

define Package/audiowrt-wpad
  SECTION:=net
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT minimal WPA2/WPA3 client + open setup AP
  URL:=https://w1.fi/
  DEPENDS:=+libnl-tiny +libubox +ucode +libucode +ucode-mod-fs +ucode-mod-nl80211 +ucode-mod-rtnl +ucode-mod-ubus +ucode-mod-uloop +libubus +libblobmsg-json +libudebug +libmbedtls
  PROVIDES:=hostapd wpa-supplicant
  USERID:=network=101:network=101
endef

define Package/audiowrt-wpad/description
 One multicall hostap binary for AudioWRT. The wpa_supplicant entry point is
 client-only and keeps WPA2-PSK, WPA3-SAE, PMF, nl80211 and OpenWrt UBus/UCode
 integration. The hostapd entry point exists only for the temporary open
 provisioning AP and omits enterprise authentication, RADIUS, VLAN, WPS,
 VHT/HE/EHT and EAP/TLS server methods. Automatic channel selection remains
 enabled because OpenWrt radios may request channel 0.
endef

TARGET_CPPFLAGS := \
	-I$(STAGING_DIR)/usr/include/libnl-tiny \
	-I$(PKG_BUILD_DIR)/src/crypto \
	$(TARGET_CPPFLAGS) \
	-DCONFIG_LIBNL20 \
	-D_GNU_SOURCE

TARGET_LDFLAGS += \
	-lubox -lubus -lblobmsg_json -lucode -lm -lnl-tiny -ludebug \
	-lmbedcrypto -lmbedx509 -lmbedtls

# Keep the build-time driver switches aligned with OpenWrt's wpad variants.
# TLS selection is a make-time option in the canonical OpenWrt recipe rather
# than a side-specific .config setting; this is important for the multicall
# crypto/link path.
DRIVER_MAKEOPTS := \
	CONFIG_ACS=y \
	CONFIG_DRIVER_NL80211=y \
	CONFIG_UCODE=y \
	CONFIG_APUP=y \
	CONFIG_TLS=mbedtls \
	CONFIG_SAE=y

define Build/Configure
	$(CP) ./files/hostapd-audiowrt.config $(PKG_BUILD_DIR)/hostapd/.config
	$(CP) ./files/wpa_supplicant-audiowrt.config $(PKG_BUILD_DIR)/wpa_supplicant/.config
endef

define Build/RunMake
	CFLAGS="$(TARGET_CPPFLAGS) $(TARGET_CFLAGS)" \
	$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR)/$(1) \
		$(TARGET_CONFIGURE_OPTS) \
		$(DRIVER_MAKEOPTS) \
		LIBS="$(TARGET_LDFLAGS)" \
		LIBS_c="$(TARGET_LDFLAGS_C)" \
		AR="$(TARGET_CROSS)gcc-ar" \
		BCHECK= \
		$(2)
endef

define Build/Compile
	echo ` \
		$(call Build/RunMake,hostapd,-s MULTICALL=1 dump_cflags); \
		$(call Build/RunMake,wpa_supplicant,-s MULTICALL=1 dump_cflags) | \
		sed -e 's,-n ,,g' -e 's^$(TARGET_CFLAGS)^^' \
	` > $(PKG_BUILD_DIR)/.cflags
	sed -i 's/"/\\"/g' $(PKG_BUILD_DIR)/.cflags

	+$(call Build/RunMake,hostapd, \
		CFLAGS="$$$$(cat $(PKG_BUILD_DIR)/.cflags)" \
		MULTICALL=1 \
		hostapd_multi.a \
	)
	+$(call Build/RunMake,wpa_supplicant, \
		CFLAGS="$$$$(cat $(PKG_BUILD_DIR)/.cflags)" \
		MULTICALL=1 \
		wpa_supplicant_multi.a \
	)

	+export MAKEFLAGS="$(MAKE_JOBSERVER)"; $(TARGET_CC) -o $(PKG_BUILD_DIR)/wpad \
		$(TARGET_CFLAGS) \
		$(AUDIOWRT_DERIVED_FILES_DIR)/multicall.c \
		$(PKG_BUILD_DIR)/hostapd/hostapd_multi.a \
		$(PKG_BUILD_DIR)/wpa_supplicant/wpa_supplicant_multi.a \
		$(TARGET_LDFLAGS)
endef

define Package/audiowrt-wpad/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/share/hostap
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/wpad $(1)/usr/sbin/
	$(LN) wpad $(1)/usr/sbin/hostapd
	$(LN) wpad $(1)/usr/sbin/wpa_supplicant
	$(INSTALL_DATA) $(AUDIOWRT_DERIVED_FILES_DIR)/hostapd.uc $(1)/usr/share/hostap/
	$(INSTALL_DATA) $(AUDIOWRT_DERIVED_FILES_DIR)/wpa_supplicant.uc $(1)/usr/share/hostap/
endef

$(eval $(call BuildPackage,audiowrt-wpad))
