#!/bin/bash
# Prepare lisaac diskman without SMART/RAID hard deps.
set -euo pipefail

rm -rf feeds/luci/applications/luci-app-diskman package/feeds/luci/luci-app-diskman
rm -rf package/luci-app-diskman /tmp/luci-app-diskman
git clone --depth=1 https://github.com/lisaac/luci-app-diskman /tmp/luci-app-diskman
if [ -d /tmp/luci-app-diskman/applications/luci-app-diskman ]; then
  cp -a /tmp/luci-app-diskman/applications/luci-app-diskman package/luci-app-diskman
else
  cp -a /tmp/luci-app-diskman package/luci-app-diskman
fi
rm -rf /tmp/luci-app-diskman
sed -i 's/+smartmontools//' package/luci-app-diskman/Makefile
# Without smartctl the controller used to return before registering any menu.
sed -i 's/{"parted", "blkid", "smartctl"}/{"parted", "blkid"}/' package/luci-app-diskman/luasrc/controller/diskman.lua
sed -i 's/+PACKAGE_$(PKG_NAME)_INCLUDE_mdadm:mdadm//' package/luci-app-diskman/Makefile
if ! grep -q '^PKGARCH:=all' package/luci-app-diskman/Makefile; then
  sed -i 's|include $(TOPDIR)/feeds/luci/luci.mk|PKGARCH:=all\ninclude $(TOPDIR)/feeds/luci/luci.mk|' package/luci-app-diskman/Makefile
fi
./scripts/feeds install luci-compat luci-app-diskman parted e2fsprogs blkid || true
