# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=dropbear
PKG_VERSION:=2025.89
PKG_RELEASE:=101

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.bz2
PKG_SOURCE_URL:=https://matt.ucc.asn.au/dropbear/releases/ https://dropbear.nl/mirror/releases/
PKG_HASH:=0d1f7ca711cfc336dc8a85e672cab9cfd8223a02fe2da0a4a7aeb58c9e113634

PKG_MAINTAINER:=AudioWRT
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE libtomcrypt/LICENSE libtommath/LICENSE
PKG_FIXUP:=autoreconf
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16 gc-sections lto

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-dropbear
  SECTION:=net
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT minimal SSH server
  PROVIDES:=dropbear
  CONFLICTS:=dropbear
endef

define Package/audiowrt-dropbear/description
 Server-only Dropbear build for constrained AudioWRT images. Client SSH/SCP,
 forwarding, X11, legacy algorithms and unrelated compatibility features are
 disabled while password and public-key administration remain available.
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
	$(INSTALL_BIN) ./files/audiowrt-dropbear.init $(1)/etc/init.d/dropbear
endef

$(eval $(call BuildPackage,audiowrt-dropbear))
