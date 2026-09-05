include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-bird
PKG_VERSION:=1.0.1
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-bird
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=BIRD2 antifilter web interface
  URL:=https://github.com/bibibi-Matrix/bird-antifilter-mikrotik
  LICENSE:=GPL-2.0-or-later
  DEPENDS:= +bird +bird2 +luci-base +rpcd +rpcd-mod-ucode +ucode-mod-fs +ucode-mod-uci
  PKGARCH:=all
endef

define Package/luci-app-bird/description
  Web interface for the BIRD2 antifilter daemon. Provides status,
  configuration and list-sync views for bird.
endef

define Build/Compile
endef

define Package/luci-app-bird/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/bird
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/bird/*.js $(1)/www/luci-static/resources/view/bird/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-bird.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-bird.json $(1)/usr/share/rpcd/acl.d/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_DATA) ./root/usr/share/rpcd/ucode/bird.uc $(1)/usr/share/rpcd/ucode/bird.uc
endef

$(eval $(call BuildPackage,luci-app-bird))
