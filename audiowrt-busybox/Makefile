# SPDX-License-Identifier: GPL-2.0-or-later

include $(TOPDIR)/rules.mk

AUDIOWRT_DERIVED_NAME:=audiowrt-busybox
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/base/utils/busybox/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk

PKG_MAINTAINER:=AudioWRT

BUSYBOX_SYM=$(if $(CONFIG_BUSYBOX_CUSTOM),CONFIG,DEFAULT)
BUSYBOX_IF_ENABLED=$(if $(CONFIG_BUSYBOX_$(BUSYBOX_SYM)_$(1)),$(2))

ifneq ($(CONFIG_BUSYBOX_$(BUSYBOX_SYM)_FEATURE_SUID),)
  PKG_FILE_MODES:=/bin/busybox:root:root:4755
endif

include $(INCLUDE_DIR)/package.mk

ifeq ($(DUMP),)
  STAMP_CONFIGURED:=$(strip $(STAMP_CONFIGURED))_$(shell grep '^CONFIG_BUSYBOX_' $(TOPDIR)/.config | $(MKHASH) md5)
endif

define Package/audiowrt-busybox
  SECTION:=base
  CATEGORY:=Base system
  TITLE:=AudioWRT BusyBox replacement
  URL:=https://busybox.net/
  DEPENDS:= +USE_GLIBC:libcrypt-compat +BUSYBOX_CONFIG_PAM:libpam +BUSYBOX_CONFIG_NTPD:jsonfilter +(USE_GLIBC&&BUSYBOX_CONFIG_FEATURE_MOUNT_NFS)||(USE_GLIBC&&BUSYBOX_CONFIG_FEATURE_INETD_RPC):libtirpc
  USERID:=ntp=123:ntp=123
  PROVIDES:=busybox
  CONFLICTS:=busybox busybox-selinux
endef

define Package/audiowrt-busybox/description
 Drop-in replacement for the BusyBox from the selected OpenWrt release. It
 inherits that release's source version, build flags, files and complete patch
 set, then additionally enables the udhcpd applet required by AudioWRT.
endef

ifneq ($(CONFIG_BUSYBOX_$(BUSYBOX_SYM)_FEATURE_SYSLOG)$(CONFIG_BUSYBOX_$(BUSYBOX_SYM)_FEATURE_SYSLOGD_CFG),)
define Package/audiowrt-busybox/conffiles/syslog
/etc/syslog.conf
endef
endif

ifneq ($(CONFIG_BUSYBOX_$(BUSYBOX_SYM)_CROND),)
define Package/audiowrt-busybox/conffiles/crond
/etc/crontabs/
endef
endif

define Package/audiowrt-busybox/conffiles
$(Package/audiowrt-busybox/conffiles/syslog)
$(Package/audiowrt-busybox/conffiles/crond)
endef

ifndef CONFIG_USE_MUSL
LDLIBS:=m crypt
endif

LDLIBS += $(call BUSYBOX_IF_ENABLED,PAM,pam pam_misc pthread)

ifeq ($(CONFIG_USE_GLIBC),y)
  LDLIBS += $(call BUSYBOX_IF_ENABLED,NSLOOKUP,resolv)
endif

ifneq ($(CONFIG_BUSYBOX_$(BUSYBOX_SYM)_FEATURE_MOUNT_NFS)$(CONFIG_BUSYBOX_$(BUSYBOX_SYM)_FEATURE_INETD_RPC),)
ifndef CONFIG_USE_MUSL
  TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include/tirpc
  LDLIBS += tirpc
endif
endif

MAKE_VARS :=
MAKE_FLAGS += \
	EXTRA_CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS)" \
	EXTRA_LDFLAGS="$(TARGET_LDFLAGS) $(TARGET_CFLAGS)" \
	LDLIBS="$(LDLIBS)" \
	LD="$(TARGET_CC)" \
	SKIP_STRIP=y
ifneq ($(findstring c,$(OPENWRT_VERBOSE)),)
  MAKE_FLAGS += V=1
endif

define Build/Configure
	rm -f $(PKG_BUILD_DIR)/.config
	touch $(PKG_BUILD_DIR)/.config
ifeq ($(DEVICE_TYPE),nas)
	echo "CONFIG_HDPARM=y" >> $(PKG_BUILD_DIR)/.config
endif
	grep 'CONFIG_BUSYBOX_$(BUSYBOX_SYM)' $(TOPDIR)/.config | sed -e "s,\\(# \\)\\?CONFIG_BUSYBOX_$(BUSYBOX_SYM)_\\(.*\\),\\1CONFIG_\\2,g" >> $(PKG_BUILD_DIR)/.config
	sed -i \
		-e '/^CONFIG_UDHCPD=/d' \
		-e '/^# CONFIG_UDHCPD is not set/d' \
		-e '/^CONFIG_DHCPD_LEASES_FILE=/d' \
		-e '/^# CONFIG_DHCPD_LEASES_FILE is not set/d' \
		$(PKG_BUILD_DIR)/.config
	echo 'CONFIG_UDHCPD=y' >> $(PKG_BUILD_DIR)/.config
	echo 'CONFIG_DHCPD_LEASES_FILE="/tmp/audiowrt-udhcpd.leases"' >> $(PKG_BUILD_DIR)/.config
	yes 'n' | $(MAKE) -C $(PKG_BUILD_DIR) $(MAKE_FLAGS) oldconfig
endef

define Build/Compile
	$(call Build/Compile/Default, \
		CONFIG_PREFIX="$(PKG_INSTALL_DIR)" \
		all install \
	)
endef

define Package/audiowrt-busybox/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/sbin
	$(CP) $(PKG_INSTALL_DIR)/* $(1)/
	$(INSTALL_DIR) $(1)/etc/profile.d
	$(INSTALL_DATA) $(AUDIOWRT_DERIVED_FILES_DIR)/busybox-history-file.sh $(1)/etc/profile.d/
ifneq ($(CONFIG_BUSYBOX_$(BUSYBOX_SYM)_FEATURE_SYSLOG)$(CONFIG_BUSYBOX_$(BUSYBOX_SYM)_FEATURE_SYSLOGD_CFG),)
	touch $(1)/etc/syslog.conf
endif
ifneq ($(CONFIG_BUSYBOX_$(BUSYBOX_SYM)_CROND),)
	$(INSTALL_BIN) $(AUDIOWRT_DERIVED_FILES_DIR)/cron $(1)/etc/init.d/cron
	$(INSTALL_DIR) $(1)/etc/crontabs
endif
ifneq ($(CONFIG_BUSYBOX_$(BUSYBOX_SYM)_NTPD),)
	$(INSTALL_BIN) $(AUDIOWRT_DERIVED_FILES_DIR)/sysntpd $(1)/etc/init.d/sysntpd
	$(INSTALL_BIN) $(AUDIOWRT_DERIVED_FILES_DIR)/ntpd-hotplug $(1)/usr/sbin/ntpd-hotplug
	$(INSTALL_DIR) $(1)/etc/capabilities $(1)/usr/share/acl.d
	$(INSTALL_DATA) $(AUDIOWRT_DERIVED_FILES_DIR)/ntpd.capabilities $(1)/etc/capabilities/ntpd.json
	$(INSTALL_DATA) $(AUDIOWRT_DERIVED_FILES_DIR)/ntpd_acl.json $(1)/usr/share/acl.d/ntpd.json
endif
	-rm -rf $(1)/lib64
endef

$(eval $(call BuildPackage,audiowrt-busybox))
