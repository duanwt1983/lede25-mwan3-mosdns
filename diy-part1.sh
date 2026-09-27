#!/bin/bash
# Before feeds update.

set -euo pipefail

if ! grep -q 'src-git passwall_packages' feeds.conf.default; then
  sed -i '1i src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main' feeds.conf.default
  sed -i '2i src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall.git;main' feeds.conf.default
fi

# Do not add iStore / nas-packages (istorex, quickstart, FastNet).
sed -i '/src-git nas /d; /src-git nas_luci /d; /src-git istore /d' feeds.conf.default || true
