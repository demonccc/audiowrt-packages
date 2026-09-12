include $(TOPDIR)/rules.mk

PKG_NAME:=mbedtls
PKG_VERSION:=3.6.7
PKG_RELEASE:=100
PKG_BUILD_FLAGS:=no-mips16 gc-sections no-lto

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.bz2
PKG_SOURCE_URL:=https://github.com/Mbed-TLS/$(PKG_NAME)/releases/download/$(PKG_NAME)-$(PKG_VERSION)
PKG_HASH:=a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6

PKG_MAINTAINER:=AudioWRT
PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_CPE_ID:=cpe:/a:arm:mbed_tls

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/audiowrt-minimal-mbedtls
  SECTION:=libs
  CATEGORY:=Libraries
  SUBMENU:=SSL
  TITLE:=AudioWRT minimal Mbed TLS library
  URL:=https://www.trustedfirmware.org/projects/mbed-tls/
  PROVIDES:=libmbedtls libmbedtls21
  CONFLICTS:=libmbedtls21
endef

define Package/audiowrt-minimal-mbedtls/description
 Mbed TLS shared libraries trimmed for AudioWRT while retaining WPA2/WPA3,
 HTTPS and APK package verification compatibility. TLS 1.2 and TLS 1.3,
 RSA/ECDSA, P-256, P-384 and X25519 remain enabled.
endef

TARGET_CFLAGS := $(filter-out -O%,$(TARGET_CFLAGS)) -Wno-unterminated-string-initialization

CMAKE_OPTIONS += \
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DUSE_SHARED_MBEDTLS_LIBRARY:Bool=ON \
	-DENABLE_TESTING:Bool=OFF \
	-DENABLE_PROGRAMS:Bool=OFF

# Start from the Mbed TLS upstream configuration and remove only algorithms
# outside AudioWRT's three consumers: wpad-basic-mbedtls, libustream-mbedtls
# and apk-mbedtls. Do not remove WPA crypto primitives or modern HTTPS paths.
MBEDTLS_UNSET_OPTIONS:= \
	MBEDTLS_ECP_DP_SECP192R1_ENABLED \
	MBEDTLS_ECP_DP_SECP224R1_ENABLED \
	MBEDTLS_ECP_DP_SECP521R1_ENABLED \
	MBEDTLS_ECP_DP_SECP192K1_ENABLED \
	MBEDTLS_ECP_DP_SECP224K1_ENABLED \
	MBEDTLS_ECP_DP_SECP256K1_ENABLED \
	MBEDTLS_ECP_DP_BP256R1_ENABLED \
	MBEDTLS_ECP_DP_BP384R1_ENABLED \
	MBEDTLS_ECP_DP_BP512R1_ENABLED \
	MBEDTLS_ECP_DP_CURVE448_ENABLED \
	MBEDTLS_KEY_EXCHANGE_PSK_ENABLED \
	MBEDTLS_KEY_EXCHANGE_DHE_PSK_ENABLED \
	MBEDTLS_KEY_EXCHANGE_ECDHE_PSK_ENABLED \
	MBEDTLS_KEY_EXCHANGE_RSA_PSK_ENABLED \
	MBEDTLS_KEY_EXCHANGE_RSA_ENABLED \
	MBEDTLS_KEY_EXCHANGE_DHE_RSA_ENABLED \
	MBEDTLS_KEY_EXCHANGE_ECDH_ECDSA_ENABLED \
	MBEDTLS_KEY_EXCHANGE_ECDH_RSA_ENABLED \
	MBEDTLS_KEY_EXCHANGE_ECJPAKE_ENABLED \
	MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_PSK_ENABLED \
	MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_PSK_EPHEMERAL_ENABLED \
	MBEDTLS_ARIA_C \
	MBEDTLS_CAMELLIA_C \
	MBEDTLS_CCM_C \
	MBEDTLS_RIPEMD160_C \
	MBEDTLS_CIPHER_MODE_OFB \
	MBEDTLS_CIPHER_MODE_XTS \
	MBEDTLS_DEBUG_C \
	MBEDTLS_PLATFORM_C \
	MBEDTLS_SELF_TEST \
	MBEDTLS_SSL_RENEGOTIATION \
	MBEDTLS_VERSION_C \
	MBEDTLS_VERSION_FEATURES

MBEDTLS_SET_OPTIONS:= \
	MBEDTLS_AES_C \
	MBEDTLS_CMAC_C \
	MBEDTLS_DES_C \
	MBEDTLS_GCM_C \
	MBEDTLS_NIST_KW_C \
	MBEDTLS_RSA_NO_CRT \
	MBEDTLS_KEY_EXCHANGE_ECDHE_RSA_ENABLED \
	MBEDTLS_KEY_EXCHANGE_ECDHE_ECDSA_ENABLED \
	MBEDTLS_ECP_DP_SECP256R1_ENABLED \
	MBEDTLS_ECP_DP_SECP384R1_ENABLED \
	MBEDTLS_ECP_DP_CURVE25519_ENABLED \
	MBEDTLS_ENTROPY_FORCE_SHA256 \
	MBEDTLS_HKDF_C \
	MBEDTLS_PSA_CRYPTO_CLIENT \
	MBEDTLS_THREADING_C \
	MBEDTLS_THREADING_PTHREAD \
	MBEDTLS_SSL_PROTO_TLS1_2 \
	MBEDTLS_SSL_PROTO_TLS1_3 \
	MBEDTLS_SSL_TLS1_3_COMPATIBILITY_MODE \
	MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_EPHEMERAL_ENABLED

define Build/Configure
	$(call Build/Configure/Default)
	$(foreach opt,$(MBEDTLS_UNSET_OPTIONS), \
		$(PKG_BUILD_DIR)/scripts/config.py \
			-f $(PKG_BUILD_DIR)/include/mbedtls/mbedtls_config.h unset $(opt);)
	$(foreach opt,$(MBEDTLS_SET_OPTIONS), \
		$(PKG_BUILD_DIR)/scripts/config.py \
			-f $(PKG_BUILD_DIR)/include/mbedtls/mbedtls_config.h set $(opt);)
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_INSTALL_DIR)/usr/include/mbedtls $(PKG_INSTALL_DIR)/usr/include/psa $(1)/usr/include/
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/lib*.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/lib*.a $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/cmake $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/mbedcrypto.pc $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/mbedtls.pc $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/mbedx509.pc $(1)/usr/lib/pkgconfig/
endef

define Package/audiowrt-minimal-mbedtls/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/lib*.so.* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,audiowrt-minimal-mbedtls))
