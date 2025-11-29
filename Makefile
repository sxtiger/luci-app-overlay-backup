cat > Makefile << 'EOF'
# Copyright (C) 2024
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-overlay-backup
PKG_VERSION:=1.0.1
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=sxtiger

LUCI_TITLE:=LuCI Overlay Backup and Restore
LUCI_DEPENDS:=+luci-base +tar +gzip
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-overlay-backup/conffiles
/etc/config/overlay_backup
endef

define Package/luci-app-overlay-backup/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	chmod +x /usr/bin/overlay-backup.sh 2>/dev/null
	chmod +x /usr/bin/overlay-restore.sh 2>/dev/null
	mkdir -p /tmp/upload
}
exit 0
endef

$(eval $(call BuildPackage,luci-app-overlay-backup))
EOF