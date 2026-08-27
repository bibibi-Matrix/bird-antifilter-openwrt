include $(TOPDIR)/rules.mk

PKG_NAME:=bird
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_BUILD_DEPENDS:=

include $(INCLUDE_DIR)/package.mk

define Package/bird
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=BIRD2 antifilter daemon with UCI configuration
  URL:=https://github.com/bibibi-Matrix/bird-antifilter-mikrotik
  LICENSE:=GPL-2.0-or-later
  DEPENDS:= +bird2 +bird2c +curl +uci
endef

define Package/bird/description
  BIRD2 routing daemon that downloads antifilter IP lists
  (antifilter.download, antifilter.network) and custom lists,
  builds a BIRD configuration and acts both as a BGP server
  (advertising the listed routes) and as a BGP client that
  installs those routes into the kernel routing table, sending
  the listed traffic through a wireguard/amneziawg interface while
  the default route stays on WAN.
endef

define Package/bird/conffiles
/etc/config/bird
endef

define Build/Compile
endef

define Package/bird/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/bird $(1)/etc/init.d/bird
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/etc/config/bird $(1)/etc/config/bird
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/80_bird $(1)/etc/uci-defaults/80_bird
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/sbin/bird-sync.sh $(1)/usr/sbin/bird-sync.sh
	$(INSTALL_DIR) $(1)/usr/share/bird/list_custom
	$(INSTALL_DATA) $(wildcard ./files/usr/share/bird/list_custom/*.lst) $(1)/usr/share/bird/list_custom/
endef

$(eval $(call BuildPackage,bird))
