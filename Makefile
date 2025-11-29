# Copyright (C) 2024
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-overlay-backup
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=sxtiger

LUCI_TITLE:=LuCI Overlay Backup and Restore
LUCI_DEPENDS:=+luci-base +tar +gzip
LUCI_PKGARCH:=all

define Package/luci-app-overlay-backup/conffiles
/etc/config/overlay_backup
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
$(eval $(call BuildPackage,luci-app-overlay-backup))
