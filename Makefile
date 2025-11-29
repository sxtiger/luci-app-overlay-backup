# Copyright (C) 2024
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-overlay-backup
PKG_VERSION:=1.0.3
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=sxtiger

LUCI_TITLE:=LuCI Overlay Backup and Restore
LUCI_DEPENDS:=+luci-base +tar +gzip
LUCI_PKGARCH:=all
LUCI_LANGUAGES:=zh_Hans
PO_FILES:=po/zh_Hans/overlay_backup.po

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-overlay-backup/conffiles
/etc/config/overlay_backup
endef

define Package/luci-app-overlay-backup/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/bin/overlay-backup.sh $(1)/usr/bin/overlay-backup.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/bin/overlay-restore.sh $(1)/usr/bin/overlay-restore.sh
	
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/root/etc/config/overlay_backup $(1)/etc/config/overlay_backup
	
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/etc/uci-defaults/99-overlay-backup $(1)/etc/uci-defaults/99-overlay-backup
	
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/luci/menu.d/luci-app-overlay-backup.json $(1)/usr/share/luci/menu.d/luci-app-overlay-backup.json
	
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/rpcd/acl.d/luci-app-overlay-backup.json $(1)/usr/share/rpcd/acl.d/luci-app-overlay-backup.json
	
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/overlay_backup
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/overlay_backup/backup.js $(1)/www/luci-static/resources/view/overlay_backup/backup.js
endef

$(eval $(call BuildPackage,luci-app-overlay-backup))