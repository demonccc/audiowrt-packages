# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

AUDIOWRT_DERIVED_NAME:=audiowrt-minimal-mpd
AUDIOWRT_CANONICAL_RECIPE:=$(TOPDIR)/feeds/packages/sound/mpd/Makefile
include $(TOPDIR)/feeds/audiowrt/include/audiowrt-openwrt-derived.mk

PKG_MAINTAINER:=AudioWRT

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/meson.mk

define Package/audiowrt-minimal-mpd
  SECTION:=sound
  CATEGORY:=AudioWRT
  TITLE:=AudioWRT FLAC-only Music Player Daemon
  URL:=https://www.musicpd.org/
  DEPENDS:=+zlib +libcurl +libpthread +boost +libfmt +alsa-lib +libflac
  USERID:=mpd:mpd
  PROVIDES:=mpd
  CONFLICTS:=mpd-mini mpd-full
endef

define Package/audiowrt-minimal-mpd/description
 MPD derived from the selected OpenWrt release and reduced to the AudioWRT
 minimal remote-playback path: MPD protocol control, HTTP input, FLAC decoding
 and ALSA output. AAC, MP3, Ogg/Vorbis, Opus, FFmpeg, UPnP, local transcoding
 and unrelated outputs are intentionally omitted.
endef

define Package/audiowrt-minimal-mpd/conffiles
/etc/mpd.conf
endef

MESON_ARGS += \
	-Db_lto=true \
	-Ddocumentation=disabled \
	-Dhtml_manual=false \
	-Dmanpages=false \
	-Dsyslog=enabled \
	-Dinotify=true \
	-Dio_uring=disabled \
	-Ddaemon=false \
	-Dsystemd=disabled \
	-Dtest=false \
	-Dfuzzer=false \
	-Depoll=true \
	-Deventfd=true \
	-Dsignalfd=true \
	-Dtcp=true \
	-Dipv6=disabled \
	-Dlocal_socket=false \
	-Ddsd=false \
	-Ddatabase=true \
	-Dlibmpdclient=disabled \
	-Dneighbor=false \
	-Dudisks=disabled \
	-Dwebdav=disabled \
	-Dcue=false \
	-Dcdio_paranoia=disabled \
	-Dcurl=enabled \
	-Dnfs=disabled \
	-Dsmbclient=disabled \
	-Dqobuz=disabled \
	-Dbzip2=disabled \
	-Diso9660=disabled \
	-Dzzip=disabled \
	-Did3tag=disabled \
	-Dchromaprint=disabled \
	-Dadplug=disabled \
	-Daudiofile=disabled \
	-Dfaad=disabled \
	-Dflac=enabled \
	-Dfluidsynth=disabled \
	-Dgme=disabled \
	-Dmikmod=disabled \
	-Dmodplug=disabled \
	-Dmpcdec=disabled \
	-Dmpg123=disabled \
	-Dopenmpt=disabled \
	-Dopus=disabled \
	-Dsidplay=disabled \
	-Dsndfile=disabled \
	-Dwavpack=disabled \
	-Dwildmidi=disabled \
	-Dvorbisenc=disabled \
	-Dlame=disabled \
	-Dtwolame=disabled \
	-Dshine=disabled \
	-Dwave_encoder=false \
	-Dlibsamplerate=disabled \
	-Dalsa=enabled \
	-Dao=disabled \
	-Dhttpd=false \
	-Djack=disabled \
	-Dopenal=disabled \
	-Doss=disabled \
	-Dpipewire=disabled \
	-Dsnapcast=false \
	-Dsndio=disabled \
	-Dsolaris_output=disabled \
	-Ddbus=disabled \
	-Dexpat=disabled \
	-Dicu=disabled \
	-Diconv=disabled \
	-Dpcre=disabled \
	-Dsqlite=disabled \
	-Dzlib=enabled \
	-Dzeroconf=disabled \
	-Dupnp=disabled \
	-Dmms=disabled \
	-Dsoundcloud=disabled \
	-Dffmpeg=disabled \
	-Dmad=disabled \
	-Dtremor=disabled \
	-Dvorbis=disabled \
	-Dfifo=false \
	-Dpipe=false \
	-Dpulse=disabled \
	-Drecorder=false \
	-Dshout=disabled \
	-Dyajl=disabled \
	-Dsoxr=disabled

define Package/audiowrt-minimal-mpd/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/mpd $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/doc/mpdconf.example $(1)/etc/mpd.conf
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(AUDIOWRT_DERIVED_FILES_DIR)/mpd.init $(1)/etc/init.d/mpd
endef

$(eval $(call BuildPackage,audiowrt-minimal-mpd))
