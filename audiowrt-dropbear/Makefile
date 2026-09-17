# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

AUDIOWRT_DERIVED_NAME:=audiowrt-dropbear
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/base/network/services/dropbear/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk

# Upstream Dropbear is target-local (`nonshared`), but this replacement must be
# emitted into the reusable AudioWRT feed so the orchestrator can collect it.
PKG_FLAGS:=
PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-dropbear
  SECTION:=net
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT minimal SSH server
  PROVIDES:=dropbear
endef

define Package/audiowrt-dropbear/description
 Server-only Dropbear derived from the selected OpenWrt release. The exact
 release source version, hardening/build flags and OpenWrt patches are inherited;
 AudioWRT only disables client-side and unrelated server features.
endef

define Package/audiowrt-dropbear/conffiles
/etc/dropbear/authorized_keys
/etc/dropbear/dropbear_ed25519_host_key
endef

CONFIGURE_ARGS += \
	--disable-pam \
	--disable-lastlog \
	--disable-loginfunc \
	--disable-pututline \
	--disable-utmp \
	--disable-wtmp \
	--disable-zlib \
	--enable-bundled-libtom

define Build/Configure
	$(call Build/Configure/Default)
	printf '%s\n' \
		'#define DROPBEAR_SERVER 1' \
		'#define DROPBEAR_CLIENT 0' \
		'#define DROPBEAR_DBCLIENT 0' \
		'#define DROPBEAR_SCP 0' \
		'#define DROPBEAR_SFTPSERVER 0' \
		'#define DROPBEAR_X11FWD 0' \
		'#define DROPBEAR_SVR_AGENTFWD 0' \
		'#define DROPBEAR_SVR_LOCALTCPFWD 0' \
		'#define DROPBEAR_SVR_REMOTETCPFWD 0' \
		'#define DROPBEAR_SVR_LOCALSTREAMFWD 0' \
		'#define DROPBEAR_CLI_AGENTFWD 0' \
		'#define DROPBEAR_CLI_LOCALTCPFWD 0' \
		'#define DROPBEAR_CLI_REMOTETCPFWD 0' \
		'#define DROPBEAR_CLI_PROXYCMD 0' \
		'#define DROPBEAR_CLI_NETCAT 0' \
		'#define DROPBEAR_DSS 0' \
		'#define DROPBEAR_RSA_SHA1 0' \
		'#define DROPBEAR_3DES 0' \
		'#define DROPBEAR_ENABLE_CBC_MODE 0' \
		'#define DROPBEAR_SHA1_HMAC 0' \
		'#define DROPBEAR_SHA1_96_HMAC 0' \
		'#define DROPBEAR_DH_GROUP1 0' \
		'#define DROPBEAR_DH_GROUP14_SHA1 0' \
		'#define DROPBEAR_ECDSA 0' \
		'#define DROPBEAR_RSA 0' \
		'#define DROPBEAR_ED25519 1' \
		'#define DROPBEAR_CURVE25519 1' \
		'#define DROPBEAR_CHACHA20POLY1305 1' \
		'#define DROPBEAR_AES128 1' \
		'#define DROPBEAR_ENABLE_CTR_MODE 1' \
		'#define DROPBEAR_SHA2_256_HMAC 1' \
		'#define DROPBEAR_SMALL_CODE 1' \
		'#define DO_MOTD 0' \
		> $(PKG_BUILD_DIR)/localoptions.h
endef

define Build/Compile
	+$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR) \
		$(TARGET_CONFIGURE_OPTS) IGNORE_SPEED=1 \
		PROGRAMS="dropbear dropbearkey" MULTI=1 SCPPROGRESS=0
endef

define Package/audiowrt-dropbear/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/bin $(1)/etc/init.d $(1)/etc/dropbear
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/dropbearmulti $(1)/usr/sbin/dropbear
	$(LN) ../sbin/dropbear $(1)/usr/bin/dropbearkey
	$(INSTALL_BIN) $(AUDIOWRT_DERIVED_FILES_DIR)/audiowrt-dropbear.init $(1)/etc/init.d/dropbear
endef

$(eval $(call BuildPackage,audiowrt-dropbear))
