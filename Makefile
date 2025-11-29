include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-overlay-backup
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0
PKG_MAINTAINER:=Your Name <your@email.com>

LUCI_TITLE:=LuCI Overlay Backup and Restore
LUCI_DESCRIPTION:=A LuCI application for backing up and restoring the overlay filesystem
LUCI_DEPENDS:=+luci-base +luci-compat +tar +gzip +block-mount
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/conffiles
/etc/config/overlay_backup
endef

# call BuildPackage - OpenWrt buildance wrapper for Build/* directives
$(eval $(call BuildPackage,$(PKG_NAME)))
