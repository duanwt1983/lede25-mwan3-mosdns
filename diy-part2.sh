#!/bin/bash
# Lean 25 extras: PassWall + mosdns, LibreSpeed LAN, bandix-plus, samba4, nginx, nft mwan3.

set -euo pipefail

# Lean's golang feed lags. Pick sbwml's newest N.x that still covers every Go
# package's go.mod (xray-core, sing-box, …) so we do not pin 26.x/27.x by hand.
golang_repo=https://github.com/sbwml/packages_lang_golang.git
go_mod_minor() {
  awk '/^go / { split($2, a, "."); if (a[1]==1 && a[2] ~ /^[0-9]+$/) print a[2]+0; exit }'
}
github_repo_from_mk() {
  sed -n 's/.*github\.com\/\([^/[:space:]]*\/[^/"[:space:]?]*\).*/\1/p' "$1" \
    | head -1 | sed 's/\.git$//; s/\/$//'
}
max_need=0
while IFS= read -r mk; do
  [ -f "$mk" ] || continue
  grep -q 'golang-package.mk' "$mk" || continue
  repo=$(github_repo_from_mk "$mk")
  ver=$(sed -n 's/^PKG_VERSION[[:space:]]*:=[[:space:]]*//p' "$mk" | head -1 | tr -d '[:space:]')
  [ -n "$repo" ] && [ -n "$ver" ] || continue
  mod=""
  for tag in "v${ver}" "${ver}"; do
    mod=$(curl -fsSL --max-time 20 "https://raw.githubusercontent.com/${repo}/${tag}/go.mod" 2>/dev/null || true)
    [ -n "$mod" ] && break
  done
  [ -n "$mod" ] || continue
  minor=$(printf '%s\n' "$mod" | go_mod_minor || true)
  [ -n "${minor:-}" ] || continue
  echo "go.mod ${repo}@${ver} requires go 1.${minor}"
  if [ "$minor" -gt "$max_need" ]; then
    max_need=$minor
  fi
done < <(find feeds package -name Makefile 2>/dev/null || true)

branches=$(git ls-remote --heads "$golang_repo" | awk -F/ '{print $NF}' | grep -E '^[0-9]+\.x$' | sort -t. -k1,1n)
[ -n "$branches" ] || { echo "ERROR: no sbwml golang N.x branches"; exit 1; }
latest=$(printf '%s\n' "$branches" | tail -1)
latest_minor=${latest%.x}
if [ "$max_need" -gt "$latest_minor" ]; then
  echo "ERROR: Go packages need go 1.${max_need} but sbwml latest is ${latest}"
  exit 1
fi
# Newer Go compiles older modules; always take the newest sbwml branch that exists.
golang_branch=$latest
echo "host golang: sbwml ${golang_branch} (packages need go 1.${max_need:-?}+)"

rm -rf feeds/packages/lang/golang package/feeds/packages/golang
git clone --depth=1 -b "$golang_branch" "$golang_repo" feeds/packages/lang/golang
if [ -x ./scripts/feeds ]; then
  ./scripts/feeds install -p packages golang 2>/dev/null || true
fi
rm -f staging_dir/hostpkg/bin/go staging_dir/host/bin/go \
  staging_dir/hostpkg/stamp/.golang* staging_dir/host/stamp/.golang* \
  staging_dir/hostpkg/stamp/.package_golang* 2>/dev/null || true
rm -rf staging_dir/hostpkg/lib/go* staging_dir/host/lib/go* \
  build_dir/hostpkg/golang* build_dir/hostpkg/go-* 2>/dev/null || true

# Drop stale mosdns copies so sbwml v5 wins. Do not remove PassWall feeds.
find . -name Makefile | grep -E '/(luci-app-mosdns|mosdns|v2ray-geodata)/Makefile$' | while read -r mk; do
  case "$mk" in
    */package/luci-app-mosdns/*|*/package/mosdns/*|*/package/v2ray-geodata/*) ;;
    *) rm -rf "$(dirname "$mk")" ;;
  esac
done || true

clone_once() {
  local dest="$1"
  local url="$2"
  local branch="${3:-}"
  if [ -d "$dest" ]; then
    echo "skip existing $dest"
    return 0
  fi
  if [ -n "$branch" ]; then
    git clone --depth=1 -b "$branch" "$url" "$dest"
  else
    git clone --depth=1 "$url" "$dest"
  fi
}

clone_once package/luci-app-mosdns https://github.com/sbwml/luci-app-mosdns v5
clone_once package/v2ray-geodata https://github.com/sbwml/v2ray-geodata
_OVERLAY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -rf package/mosdns-mwan
cp -a "$_OVERLAY/package/mosdns-mwan" package/mosdns-mwan
rm -rf package/wireshark
cp -a "$_OVERLAY/package/wireshark" package/wireshark
# Overlay scripts must be executable in the image. Git on Windows often stores
# them as 100644; fix the index when possible, then chmod the working tree.
[ -f scripts/fix-overlay-exec.sh ] && sh scripts/fix-overlay-exec.sh || true
lede_chmod_overlay_exec() {
  local f
  for f in \
    files/etc/init.d/* \
    files/etc/hotplug.d/*/* \
    files/usr/libexec/* \
    files/usr/libexec/rpcd/* \
    files/usr/sbin/* \
    package/mosdns-mwan/files/etc/hotplug.d/*/* \
    package/mosdns-mwan/files/usr/libexec/* \
    package/mosdns-mwan/files/usr/sbin/* \
    package/mosdns-mwan/files/usr/share/mosdns/*; do
    [ -f "$f" ] || continue
    head -c 2 "$f" 2>/dev/null | grep -q '^#!' || continue
    chmod 755 "$f" 2>/dev/null || true
  done
}
lede_chmod_overlay_exec
# Windows editors may leave CR; firmware runs on Linux.
lede_strip_overlay_cr() {
  find files \
    \( -name '*.sh' -o -name '*.uc' -o -name '*.js' -o -name '*.json' \
       -o -path '*/init.d/*' -o -path '*/hotplug.d/*/*' \
       -o -path '*/uci-defaults/*' -o -path '*/libexec/*' \
       -o -path '*/usr/sbin/*' \) -type f 2>/dev/null \
  | while read -r f; do
    [ -f "$f" ] || continue
    sed -i 's/\r$//' "$f"
  done
}
lede_strip_overlay_cr

# ubusd/rpcd default nofile=1024; long-open topology + WAN monitor exhausts it.
lede_bump_ubus_nofile() {
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -q 'nofile=' "$f" && continue
    grep -q 'procd_set_param respawn' "$f" || continue
    sed -i '/procd_set_param respawn/a\
	procd_set_param limits nofile="65535 65535"
' "$f" || true
  done < <(find package feeds -name 'ubus.init' -o -name 'rpcd.init' 2>/dev/null || true)
}
lede_bump_ubus_nofile

_NGINX_UBUS_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches/nginx-ubus/apply.sh"
if [ -f "$_NGINX_UBUS_PATCH" ]; then
  sh "$_NGINX_UBUS_PATCH" "$(pwd)"
fi

_DNSMASQ_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches/dnsmasq/apply.sh"
if [ -f "$_DNSMASQ_PATCH" ]; then
  sh "$_DNSMASQ_PATCH" .
fi

_MOSDNS_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches/luci-app-mosdns/apply.sh"
if [ -x "$_MOSDNS_PATCH" ] || [ -f "$_MOSDNS_PATCH" ]; then
  sh "$_MOSDNS_PATCH" "$(pwd)"
fi

# LAN speedtest is librespeed-go. Lean's packages feed does not ship it.
rm -rf package/luci-app-netspeedtest package/ookla-speedtest package/homebox /tmp/netspeedtest
rm -rf package/librespeed-go /tmp/owrt-packages-ls
git clone --depth=1 --filter=blob:none --sparse https://github.com/openwrt/packages /tmp/owrt-packages-ls
git -C /tmp/owrt-packages-ls sparse-checkout set net/librespeed-go
cp -a /tmp/owrt-packages-ls/net/librespeed-go package/librespeed-go
rm -rf /tmp/owrt-packages-ls
sed -i 's|include ../../lang/golang/golang-package.mk|include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|' \
  package/librespeed-go/Makefile
[ -f package/librespeed-go/Makefile ] || { echo "ERROR: librespeed-go Makefile missing"; exit 1; }
rm -rf feeds/luci/applications/luci-app-netspeedtest package/feeds/luci/luci-app-netspeedtest || true

# Bandix Plus: eBPF per-device traffic stats + per-MAC rate limits.
# Upstream repos now nest the OpenWrt package one level down (…/openwrt-bandix-plus/, …/luci-app-bandix-plus/).
rm -rf package/bandix-plus package/luci-app-bandix-plus package/openwrt-bandix-plus /tmp/openwrt-bandix-plus /tmp/luci-app-bandix-plus
git clone --depth=1 https://github.com/timsaya/openwrt-bandix-plus /tmp/openwrt-bandix-plus
git clone --depth=1 https://github.com/timsaya/luci-app-bandix-plus /tmp/luci-app-bandix-plus
if [ -f /tmp/openwrt-bandix-plus/openwrt-bandix-plus/Makefile ]; then
  cp -a /tmp/openwrt-bandix-plus/openwrt-bandix-plus package/bandix-plus
else
  echo "ERROR: openwrt-bandix-plus nested Makefile missing"
  exit 1
fi
if [ -f /tmp/luci-app-bandix-plus/luci-app-bandix-plus/Makefile ]; then
  cp -a /tmp/luci-app-bandix-plus/luci-app-bandix-plus package/luci-app-bandix-plus
else
  echo "ERROR: luci-app-bandix-plus nested Makefile missing"
  exit 1
fi
rm -rf /tmp/openwrt-bandix-plus /tmp/luci-app-bandix-plus
rm -rf feeds/luci/applications/luci-app-bandix-plus package/feeds/luci/luci-app-bandix-plus || true
_LUCI_BANDIX_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches/luci-app-bandix-plus/apply.sh"
[ -x "$_LUCI_BANDIX_PATCH" ] && "$_LUCI_BANDIX_PATCH" || bash "$_LUCI_BANDIX_PATCH" 2>/dev/null || true

rm -rf package/ddns-go package/luci-app-ddns-go /tmp/luci-app-ddns-go
git clone --depth=1 https://github.com/sirpdboy/luci-app-ddns-go /tmp/luci-app-ddns-go
if [ -d /tmp/luci-app-ddns-go/ddns-go ]; then
  cp -a /tmp/luci-app-ddns-go/ddns-go package/ddns-go
  cp -a /tmp/luci-app-ddns-go/luci-app-ddns-go package/luci-app-ddns-go
else
  cp -a /tmp/luci-app-ddns-go package/luci-app-ddns-go
fi
rm -rf feeds/luci/applications/luci-app-ddns-go feeds/packages/net/ddns-go || true

# Feed copies + leftover symlinks cause "incompatible architecture" at image install.
rm -rf feeds/luci/themes/luci-theme-argon feeds/luci/applications/luci-app-argon-config
rm -rf package/feeds/luci/luci-theme-argon package/feeds/luci/luci-app-argon-config
clone_once package/luci-theme-argon https://github.com/jerrykuku/luci-theme-argon
clone_once package/luci-app-argon-config https://github.com/jerrykuku/luci-app-argon-config
for mk in package/luci-theme-argon/Makefile package/luci-app-argon-config/Makefile; do
  if [ -f "$mk" ] && ! grep -q '^PKGARCH:=all' "$mk"; then
    sed -i 's|include $(TOPDIR)/feeds/luci/luci.mk|PKGARCH:=all\ninclude $(TOPDIR)/feeds/luci/luci.mk|' "$mk"
  fi
done
_LUCI_ARGON_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches/luci-theme-argon/apply.sh"
if [ -f "$_LUCI_ARGON_PATCH" ]; then
  sh "$_LUCI_ARGON_PATCH" .
fi
for _lede_brand in \
	files/www/luci-static/argon/css/lede-brand-font.css \
	files/www/luci-static/argon/font/DuanNingMaoBiXingShuWanZhengBan-2.ttf \
	files/usr/share/ucode/luci/template/themes/argon/header.ut; do
	[ -f "$_lede_brand" ] || { echo "ERROR: brand asset missing: $_lede_brand"; exit 1; }
done
grep -q displayName files/usr/share/ucode/luci/template/themes/argon/header.ut \
	|| { echo "ERROR: brand header.ut missing displayName"; exit 1; }
grep -q lede-brand-font files/usr/share/ucode/luci/template/themes/argon/header.ut \
	|| { echo "ERROR: brand header.ut missing lede-brand-font.css"; exit 1; }
echo "brand title/font overlay OK"
# Lean luci already ships diskman; that copy hard-depends on smartmontools.
# Using only lisaac's tree lets us drop SMART/RAID deps without breaking install.
rm -rf feeds/luci/applications/luci-app-diskman package/feeds/luci/luci-app-diskman
rm -rf package/luci-app-diskman package/parted /tmp/luci-app-diskman
git clone --depth=1 https://github.com/lisaac/luci-app-diskman /tmp/luci-app-diskman
if [ -d /tmp/luci-app-diskman/applications/luci-app-diskman ]; then
  cp -a /tmp/luci-app-diskman/applications/luci-app-diskman package/luci-app-diskman
elif [ -d /tmp/luci-app-diskman/luci-app-diskman ]; then
  cp -a /tmp/luci-app-diskman/luci-app-diskman package/luci-app-diskman
else
  cp -a /tmp/luci-app-diskman package/luci-app-diskman
fi
rm -rf /tmp/luci-app-diskman
sed -i 's/+smartmontools//' package/luci-app-diskman/Makefile
sed -i 's/{"parted", "blkid", "smartctl"}/{"parted", "blkid"}/' package/luci-app-diskman/luasrc/controller/diskman.lua
sed -i 's/+PACKAGE_$(PKG_NAME)_INCLUDE_mdadm:mdadm//' package/luci-app-diskman/Makefile
if ! grep -q '^PKGARCH:=all' package/luci-app-diskman/Makefile; then
  sed -i 's|include $(TOPDIR)/feeds/luci/luci.mk|PKGARCH:=all\ninclude $(TOPDIR)/feeds/luci/luci.mk|' package/luci-app-diskman/Makefile
fi

rm -rf package/luci-app-filemanager /tmp/owrt-luci
git clone --depth=1 --filter=blob:none --sparse https://github.com/openwrt/luci /tmp/owrt-luci
git -C /tmp/owrt-luci sparse-checkout set applications/luci-app-filemanager
cp -a /tmp/owrt-luci/applications/luci-app-filemanager package/luci-app-filemanager
rm -rf /tmp/owrt-luci
sed -i 's|include ../../luci.mk|include $(TOPDIR)/feeds/luci/luci.mk|' package/luci-app-filemanager/Makefile

# Official mwan3 needs iptables-nft. Use the nftables port so firewall stays fw4-only.
rm -rf feeds/packages/net/mwan3 feeds/luci/applications/luci-app-mwan3
rm -rf package/feeds/packages/mwan3 package/feeds/luci/luci-app-mwan3
rm -rf package/mwan3 package/luci-app-mwan3
git clone --depth=1 -b openwrt-25.12 https://github.com/dl12345/mwan3 package/mwan3
git clone --depth=1 -b openwrt-25.12 https://github.com/dl12345/luci-app-mwan3 package/luci-app-mwan3
# Dual WAN: netifd only puts the lowest-metric default in main. Copy-from-main
# then never installs a default in the higher-metric WAN's table (two PPPoE
# lines that share a CGNAT peer are the usual trigger). Synthesize from ubus.
_MWAN3_PATCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches/mwan3"
if [ -f "$_MWAN3_PATCH_ROOT/mwan3-create-iface-route.uc" ]; then
  cp "$_MWAN3_PATCH_ROOT/mwan3-create-iface-route.uc" \
    package/mwan3/files/lib/mwan3/mwan3-create-iface-route.uc
fi
if [ -f "$_MWAN3_PATCH_ROOT/mwan3rtmon" ]; then
  cp "$_MWAN3_PATCH_ROOT/mwan3rtmon" package/mwan3/files/usr/sbin/mwan3rtmon
  chmod 755 package/mwan3/files/usr/sbin/mwan3rtmon
fi
# luci-app-mwan3 Status: ui.Table sort calls hasAttribute on Text nodes.
_LUCI_MWAN3_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches/luci-app-mwan3"
if [ -f "$_LUCI_MWAN3_PATCH/detail.js" ]; then
  cp "$_LUCI_MWAN3_PATCH/detail.js" \
    package/luci-app-mwan3/htdocs/luci-static/resources/view/mwan3/status/detail.js
fi
if [ -f "$_LUCI_MWAN3_PATCH/overview.js" ]; then
  cp "$_LUCI_MWAN3_PATCH/overview.js" \
    package/luci-app-mwan3/htdocs/luci-static/resources/view/mwan3/status/overview.js
fi
if [ -f "$_LUCI_MWAN3_PATCH/apply-isp.sh" ]; then
  sh "$_LUCI_MWAN3_PATCH/apply-isp.sh" .
fi
if [ -f files/www/luci-static/resources/view/mwan3/ispupdate.js ]; then
  _ISPJS="$(find package/luci-app-mwan3 -path '*/view/mwan3/ispupdate.js' -type f 2>/dev/null | head -n 1)"
  if [ -z "$_ISPJS" ]; then
    mkdir -p package/luci-app-mwan3/htdocs/luci-static/resources/view/mwan3 2>/dev/null || true
    _ISPJS="package/luci-app-mwan3/htdocs/luci-static/resources/view/mwan3/ispupdate.js"
  fi
  if [ -d "$(dirname "$_ISPJS")" ]; then
    cp files/www/luci-static/resources/view/mwan3/ispupdate.js "$_ISPJS"
    echo "mwan3 isp: installed $_ISPJS"
  fi
fi
if [ -f files/www/luci-static/resources/view/mwan3/network/globals.js ]; then
  _GJS="$(find package/luci-app-mwan3 -path '*/view/mwan3/network/globals.js' -type f | head -n 1)"
  if [ -n "$_GJS" ]; then
    cp files/www/luci-static/resources/view/mwan3/network/globals.js "$_GJS"
    echo "mwan3 globals: replaced $_GJS"
  fi
fi
if [ -f files/usr/libexec/lede-mwan3-setup ]; then
  mkdir -p package/mwan3/files/usr/libexec 2>/dev/null || true
  if [ -d package/mwan3/files/usr/libexec ]; then
    install -m 0755 files/usr/libexec/lede-mwan3-setup package/mwan3/files/usr/libexec/lede-mwan3-setup
    echo "mwan3: installed lede-mwan3-setup"
  fi
fi
if [ -f files/lib/functions/lede-mwan3.sh ]; then
  mkdir -p package/mwan3/files/lib/functions 2>/dev/null || true
  if [ -d package/mwan3/files/lib/functions ]; then
    install -m 0644 files/lib/functions/lede-mwan3.sh package/mwan3/files/lib/functions/lede-mwan3.sh
    echo "mwan3: installed lede-mwan3.sh"
  fi
fi
# lede-theme-page.js / lede-fullwidth.js live in files/ overlay only.
# Baking them into both luci-app-mwan3 and luci-mod-status IPKs breaks opkg at package/install.
if [ -f files/etc/hotplug.d/dhcp/30-lede-mwan3-mac ]; then
  mkdir -p package/mwan3/files/etc/hotplug.d/dhcp 2>/dev/null || true
  if [ -d package/mwan3/files/etc/hotplug.d/dhcp ]; then
    install -m 0755 files/etc/hotplug.d/dhcp/30-lede-mwan3-mac \
      package/mwan3/files/etc/hotplug.d/dhcp/30-lede-mwan3-mac
  fi
fi
if [ -f files/etc/hotplug.d/iface/26-wan-alert ]; then
  mkdir -p package/mosdns-mwan/files/etc/hotplug.d/iface 2>/dev/null || true
  install -m 0755 files/etc/hotplug.d/iface/26-wan-alert \
    package/mosdns-mwan/files/etc/hotplug.d/iface/26-wan-alert 2>/dev/null || true
fi
if [ -f files/etc/hotplug.d/net/90-lede-wan-carrier ]; then
  mkdir -p package/mosdns-mwan/files/etc/hotplug.d/net 2>/dev/null || true
  install -m 0755 files/etc/hotplug.d/net/90-lede-wan-carrier \
    package/mosdns-mwan/files/etc/hotplug.d/net/90-lede-wan-carrier 2>/dev/null || true
fi
sed -i 's|include ../../luci.mk|include $(TOPDIR)/feeds/luci/luci.mk|' package/luci-app-mwan3/Makefile
if ! grep -q '^PKGARCH:=all' package/luci-app-mwan3/Makefile; then
  sed -i 's|include $(TOPDIR)/feeds/luci/luci.mk|PKGARCH:=all\ninclude $(TOPDIR)/feeds/luci/luci.mk|' package/luci-app-mwan3/Makefile
fi
# Lean package name uses hyphens; the nft port Makefile uses underscores.
sed -i 's/libnetfilter_conntrack/libnetfilter-conntrack/g' package/mwan3/Makefile

# samba4 -> gettext-full/host. Lean 0.22.5 tarball is already bootstrapped.
if [ -f package/libs/gettext-full/Makefile ]; then
  sed -i \
    -e '/call Host\/Bootstrap/d' \
    -e '/call Build\/Bootstrap/d' \
    -e '/^PKG_FIXUP:=autoreconf/d' \
    -e '/^export GNULIB_SRCDIR/d' \
    package/libs/gettext-full/Makefile
fi

# Image install reads DEFAULT_PACKAGES even when those configs are disabled.
# That is why 33953034108 compiled for ~2h then failed on aliyun/dnspod/argon/i18n.
python3 - <<'PY'
from pathlib import Path
import re

p = Path("include/target.mk")
text = p.read_text()
pat = re.compile(
    r"^DEFAULT_PACKAGES\.router:=\\(?:\n[^\n]*\\)*\n[^\n]*\n",
    re.M,
)
new_router = (
    "DEFAULT_PACKAGES.router:=\\\n"
    "\tdnsmasq-full firewall4 nftables-json ppp ppp-mod-pppoe odhcp6c odhcpd-ipv6only \\\n"
    "\tblock-mount coremark kmod-nf-nathelper kmod-nf-nathelper-extra kmod-tun \\\n"
    "\tluci-app-diskman luci-i18n-diskman-zh-cn parted blkid \\\n"
    "\tkmod-fs-ext4 kmod-fs-ntfs3 kmod-fs-exfat kmod-usb-storage kmod-usb-storage-uas kmod-ixgbe \\\n"
    "\tip-full default-settings luci-nginx luci-proto-ipv6 curl ca-certificates\n"
)
text2, n = pat.subn(new_router, text, count=1)
if n != 1:
    raise SystemExit(f"DEFAULT_PACKAGES.router replace failed (matches={n})")
if any(s in text2 for s in ("ddns-scripts_aliyun", "luci-app-ssr-plus", "luci-app-arpbind")):
    raise SystemExit("old Lean router defaults still present after patch")
p.write_text(text2)

x86 = Path("target/linux/x86/Makefile")
if x86.exists():
    t = re.sub(r"\bautosamba\b", "", x86.read_text())
    x86.write_text(t)
print("patched DEFAULT_PACKAGES.router:")
print(new_router)
PY

sed -i 's/192.168.1.1/192.168.9.1/g' package/base-files/files/bin/config_generate || true
if [ -f package/lean/default-settings/files/zzz-default-settings ]; then
  sed -i 's/192.168.1.1/192.168.9.1/g' package/lean/default-settings/files/zzz-default-settings || true
  sed -i -E 's/^([[:space:]]*iptables)/# \1/' package/lean/default-settings/files/zzz-default-settings || true
  sed -i -E 's/^([[:space:]]*ip6tables)/# \1/' package/lean/default-settings/files/zzz-default-settings || true
fi

sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile || true
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-light/Makefile || true
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-nginx/Makefile || true
# Do not rewrite luci-light to nginx-mod-luci: that creates a kconfig cycle.
# Keep luci-light / luci-ssl unselected so uhttpd stays out.

if [ ! -d feeds/luci/collections/luci-nginx ]; then
  echo "missing feeds/luci/collections/luci-nginx"
  exit 1
fi
if ! grep -Rqs --include=Makefile 'Package/nftables-json' package/network/utils/nftables 2>/dev/null; then
  echo "missing nftables-json; mwan3 nft port cannot be selected"
  exit 1
fi

_IFACE_DHCP_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches/luci-mod-network/apply.sh"
if [ -x "$_IFACE_DHCP_PATCH" ] || [ -f "$_IFACE_DHCP_PATCH" ]; then
  sh "$_IFACE_DHCP_PATCH" .
fi
_LUCI_SYSTEM_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches/luci-mod-system/apply.sh"
if [ -f "$_LUCI_SYSTEM_PATCH" ]; then
  sh "$_LUCI_SYSTEM_PATCH" .
fi
if [ -f files/www/luci-static/resources/view/network/iface-dhcp-extra.js ]; then
  find feeds/luci package -path '*/view/network/interfaces.js' -type f 2>/dev/null | while read -r f; do
    cp files/www/luci-static/resources/view/network/iface-dhcp-extra.js "$(dirname "$f")/iface-dhcp-extra.js"
    echo "dhcp extra: $(dirname "$f")/iface-dhcp-extra.js"
  done
fi
if [ -f files/www/luci-static/resources/view/network/iface-bw-extra.js ]; then
  find feeds/luci package -path '*/view/network/interfaces.js' -type f 2>/dev/null | while read -r f; do
    cp files/www/luci-static/resources/view/network/iface-bw-extra.js "$(dirname "$f")/iface-bw-extra.js"
    echo "bw extra: $(dirname "$f")/iface-bw-extra.js"
  done
fi
if [ -f files/www/luci-static/resources/view/network/netspeed.js ]; then
  find feeds/luci package -path '*/view/network/interfaces.js' -type f 2>/dev/null | while read -r f; do
    cp files/www/luci-static/resources/view/network/netspeed.js "$(dirname "$f")/netspeed.js"
    echo "netspeed: $(dirname "$f")/netspeed.js"
  done
fi
if [ -f files/www/luci-static/resources/view/network/packetcap.js ]; then
  find feeds/luci package -path '*/view/network/interfaces.js' -type f 2>/dev/null | while read -r f; do
    cp files/www/luci-static/resources/view/network/packetcap.js "$(dirname "$f")/packetcap.js"
    echo "packetcap: $(dirname "$f")/packetcap.js"
  done
fi
if [ -f files/www/luci-static/resources/view/network/lansec.js ]; then
  find feeds/luci package -path '*/view/network/interfaces.js' -type f 2>/dev/null | while read -r f; do
    cp files/www/luci-static/resources/view/network/lansec.js "$(dirname "$f")/lansec.js"
    echo "lansec: $(dirname "$f")/lansec.js"
  done
fi
if [ -f files/www/luci-static/resources/view/system/remote.js ]; then
  find feeds/luci package -path '*/view/system/system.js' -type f 2>/dev/null | while read -r f; do
    case "$f" in
      */luci-mod-system/*)
        cp files/www/luci-static/resources/view/system/remote.js "$(dirname "$f")/remote.js"
        echo "remote: installed $(dirname "$f")/remote.js"
        ;;
    esac
  done
fi

if [ -f files/www/luci-static/resources/view/system/crontab.js ]; then
  find feeds/luci package -path '*/view/system/crontab.js' -type f 2>/dev/null | while read -r f; do
    case "$f" in
      */luci-mod-system/*)
        cp files/www/luci-static/resources/view/system/crontab.js "$f"
        echo "crontab: replaced $f"
        ;;
    esac
  done
fi

if [ -f files/www/luci-static/resources/view/status/index.js ]; then
  find feeds/luci package -path '*/view/status/index.js' -type f 2>/dev/null | while read -r f; do
    case "$f" in
      */luci-mod-status/*)
        cp files/www/luci-static/resources/view/status/index.js "$f"
        echo "overview: replaced $f"
        if [ -f files/www/luci-static/resources/view/status/ratechart.js ]; then
          cp files/www/luci-static/resources/view/status/ratechart.js "$(dirname "$f")/ratechart.js"
          echo "overview: installed $(dirname "$f")/ratechart.js"
        fi
		if [ -f files/www/luci-static/resources/view/status/syslog.js ]; then
          cp files/www/luci-static/resources/view/status/syslog.js "$(dirname "$f")/syslog.js"
          echo "syslog: replaced $f with readable syslog.js"
        fi
        for extra in logcenter.js loghub.js alertlog.js wanalert.js alertmap.js mosdnscache.js wanalert-page.js wanalert-layout.js; do
          if [ -f "files/www/luci-static/resources/view/status/$extra" ]; then
            cp "files/www/luci-static/resources/view/status/$extra" "$(dirname "$f")/$extra"
            echo "status: installed $(dirname "$f")/$extra"
          fi
        done
        ;;
    esac
  done
fi

python3 - <<'PY' || true
from pathlib import Path
import json
hide = {"admin/status/syslog", "admin/status/alertlog", "admin/status/logs", "admin/status/logs/syslog", "admin/status/logs/dmesg"}
realtime_views = ("load.js", "bandwidth.js", "wireless.js", "connections.js")
for p in Path(".").glob("**/luci-mod-status/**/menu.d/*.json"):
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    changed = False
    for k in list(data):
        if k in hide or k.startswith("admin/status/realtime"):
            del data[k]
            changed = True
    if "admin/status/overview" in data:
        dep = data["admin/status/overview"].setdefault("depends", {})
        acl = dep.get("acl") or []
        if "luci-app-wan-monitor" not in acl:
            dep["acl"] = list(acl) + ["luci-app-wan-monitor"]
            changed = True
    if changed:
        p.write_text(json.dumps(data, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
        print("hid status log/realtime menus", p)

for p in Path(".").glob("**/luci-mod-status/**/rpcd/acl.d/luci-mod-status.json"):
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    if "luci-mod-status-realtime" in data:
        del data["luci-mod-status-realtime"]
        p.write_text(json.dumps(data, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
        print("removed luci-mod-status-realtime acl", p)

for name in realtime_views:
    for p in Path(".").glob(f"**/luci-mod-status/**/view/status/{name}"):
        try:
            p.unlink()
            print("removed realtime view", p)
        except Exception:
            pass

for p in Path(".").glob("**/rpcd/acl.d/luci-mod-status-index.json"):
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    idx = data.get("luci-mod-status-index")
    if not isinstance(idx, dict):
        continue
    ubus = idx.setdefault("read", {}).setdefault("ubus", {})
    methods = ubus.get("wanmonitor") or []
    for extra in ("snapshot", "layout_get"):
        if extra not in methods:
            methods.append(extra)
    ubus["wanmonitor"] = methods
    wubus = idx.setdefault("write", {}).setdefault("ubus", {})
    wmethods = wubus.get("wanmonitor") or []
    if "layout_set" not in wmethods:
        wmethods.append("layout_set")
    for extra in ("wan_restart", "gateway_reboot"):
        if extra not in wmethods:
            wmethods.append(extra)
    wubus["wanmonitor"] = wmethods
    p.write_text(json.dumps(data, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print("acl: wanmonitor layout on", p)

for p in Path(".").glob("**/luci-app-samba4/**/menu.d/*.json"):
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    if "admin/nas/samba4" not in data and "admin/services/samba4" not in data:
        continue
    data.pop("admin/nas/samba4", None)
    data["admin/services/samba4"] = {
        "title": "网络共享",
        "order": 80,
        "action": {"type": "view", "path": "samba4"},
        "depends": {"acl": ["luci-app-samba4"], "uci": {"samba4": True}},
    }
    p.write_text(json.dumps(data, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print("samba menu -> services", p)

for p in Path(".").glob("**/luci-base/**/menu.d/*.json"):
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    if "admin/nas" in data and data["admin/nas"].get("enabled") is not False:
        data["admin/nas"]["enabled"] = False
        p.write_text(json.dumps(data, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
        print("disabled NAS menu", p)
PY

# Only install packages that still live in feeds. Names already cloned into
# package/ (mosdns, argon, ddns-go, diskman, mwan3 nft, librespeed-go, …)
# must not be passed to feeds install: that prints
# "WARNING: Not overriding core package" and does not drop them from the image.
./scripts/feeds install \
  luci-app-passwall \
  luci-app-samba4 samba4-server samba4 \
  luci-nginx nginx nginx-mod-luci \
  uwsgi uwsgi-luci-support \
  parted blkid \
  || true

assert_pkg() {
  local n="$1" mk=""
  mk=$(find package feeds -path "*/${n}/Makefile" 2>/dev/null | head -n 1 || true)
  if [ -z "$mk" ]; then
    echo "ERROR: $n has no Makefile; it will NOT be in the firmware"
    exit 1
  fi
  echo "package $n <- $mk"
}
assert_pkg luci-app-mosdns
assert_pkg mosdns
assert_pkg mosdns-mwan
assert_pkg ddns-go
assert_pkg luci-app-ddns-go
assert_pkg luci-theme-argon
assert_pkg luci-app-argon-config
assert_pkg librespeed-go
assert_pkg bandix-plus
assert_pkg luci-app-bandix-plus
assert_pkg luci-app-diskman
assert_pkg mwan3
assert_pkg luci-app-mwan3
assert_pkg luci-app-passwall
assert_pkg luci-app-samba4
assert_pkg tcpdump
assert_pkg wireshark

rm -rf feeds/luci/applications/luci-app-diskman package/feeds/luci/luci-app-diskman
if grep -q '+smartmontools' package/luci-app-diskman/Makefile; then
  echo "luci-app-diskman still hard-depends on smartmontools"
  exit 1
fi
if [ -d feeds/luci/applications/luci-app-diskman ]; then
  echo "Lean luci-app-diskman feed copy came back"
  exit 1
fi

# --- LEDE overlay compile self-check (replaces ad-hoc hotfix scripts) ---
echo "--- LEDE overlay compile self-check ---"
_LEDE_FILES="files"
if [ ! -d "$_LEDE_FILES" ]; then
  _LEDE_FILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/files"
fi
[ -d "$_LEDE_FILES" ] || { echo "ERROR: files/ overlay directory not found"; exit 1; }

assert_overlay() {
  local rel="$1"
  local f="$_LEDE_FILES/$rel"
  [ -f "$f" ] || { echo "ERROR: missing overlay file: $f"; exit 1; }
  echo "overlay OK: $rel"
}

assert_grep() {
  local needle="$1" file="$2"
  grep -Fq "$needle" "$file" || {
    echo "ERROR: $(basename "$file") missing expected content: $needle"
    exit 1
  }
  echo "content OK: $needle"
}

assert_absent() {
  local needle="$1" file="$2"
  if grep -Fq "$needle" "$file"; then
    echo "ERROR: $(basename "$file") still has removed content: $needle"
    exit 1
  fi
  echo "absent OK: $needle"
}

assert_pkg_file() {
  local needle="$1"
  shift
  local f
  f=$(find "$@" -type f 2>/dev/null | head -n 1 || true)
  [ -n "$f" ] || { echo "ERROR: package file not found ($*)"; exit 1; }
  assert_grep "$needle" "$f"
  echo "package OK: $f"
}

for _rel in \
  www/luci-static/resources/lede-theme-page.js \
  www/luci-static/resources/lede-fullwidth.js \
  www/luci-static/resources/view/mwan3/network/globals.js \
  www/luci-static/resources/view/status/index.js \
  www/luci-static/resources/view/status/wanalert-page.js \
  www/luci-static/resources/view/status/wanalert-layout.js \
  www/luci-static/argon/css/lede-brand-font.css \
  www/luci-static/argon/font/DuanNingMaoBiXingShuWanZhengBan-2.ttf \
  usr/share/ucode/luci/template/themes/argon/header.ut \
  usr/share/ucode/luci/template/themes/argon/header_login.ut \
  usr/share/ucode/luci/template/themes/argon/sysauth.ut \
  usr/share/luci/menu.d/zzz-luci-mwan3-tab.json \
  usr/share/luci/menu.d/luci-mwan3-isp.json \
  usr/share/rpcd/acl.d/luci-mwan3-isp.json \
  usr/share/rpcd/ucode/luci.isp-ip.uc \
  usr/libexec/isp-ip-update \
  etc/init.d/isp-ip-update \
  etc/config/isp-ip \
  usr/libexec/mosdns-fix-dns-forward \
  usr/libexec/lede-mwan3-setup \
  lib/functions/lede-mwan3.sh \
  www/luci-static/resources/view/mwan3/ispupdate.js \
  usr/libexec/lede-autolimit \
  usr/libexec/lede-autolimit-loop \
  usr/libexec/rpcd/lede-autolimit \
  etc/init.d/lede-autolimit \
  etc/config/lede-autolimit \
  etc/uci-defaults/43-lede-autolimit \
  usr/share/ucode/lede-autolimit.uc \
  www/luci-static/resources/view/status/autolimit.js \
  usr/libexec/lede-data-setup \
  etc/init.d/lede-data \
  etc/uci-defaults/10-lede-data-enable \
  etc/uci-defaults/11-lede-fstab-data \
  usr/libexec/lede-autofix \
  usr/share/ucode/lede-bandix.uc \
  usr/share/ucode/lede-watch.uc \
  usr/libexec/rpcd/wanmonitor \
  usr/libexec/wan-alert \
  usr/libexec/lede-lansec \
  etc/init.d/lede-lansec \
  etc/config/lede-lansec \
  etc/uci-defaults/60-lede-lansec \
  etc/hotplug.d/iface/29-lede-lansec \
  www/luci-static/resources/view/network/lansec.js \
  usr/share/luci/menu.d/luci-lede-lansec.json \
  usr/share/rpcd/acl.d/luci-lede-lansec.json \
  www/luci-static/resources/view/status/alertmap.js \
  www/luci-static/resources/view/status/alertlog.js \
  etc/config/wanalert \
  etc/uci-defaults/50-wanalert-alert-flags \
  usr/libexec/packet-cap \
  etc/hotplug.d/net/90-lede-wan-carrier \
  etc/hotplug.d/iface/28-bandix-plus-restart \
  etc/hotplug.d/dhcp/30-lede-mwan3-mac \
  usr/sbin/wan-fail-dump \
  usr/sbin/wan-fail-watch
do
  assert_overlay "$_rel"
done

_DNSMASQ_MK=$(find package/network/services/dnsmasq -name Makefile -type f 2>/dev/null | head -n 1 || true)
[ -n "$_DNSMASQ_MK" ] || { echo "ERROR: dnsmasq Makefile not found"; exit 1; }
assert_grep 'PKG_UPSTREAM_VERSION:=2.93' "$_DNSMASQ_MK"
echo "package OK: dnsmasq 2.93"

assert_grep 'lede-theme-page' "$_LEDE_FILES/www/luci-static/resources/view/status/index.js"
assert_grep 'lede-theme-page' "$_LEDE_FILES/www/luci-static/resources/view/mwan3/network/globals.js"
assert_grep 'commitDisableToUci' "$_LEDE_FILES/www/luci-static/resources/view/mwan3/network/globals.js"
assert_grep 'displayName' "$_LEDE_FILES/usr/share/ucode/luci/template/themes/argon/header.ut"
assert_grep 'lede-brand-font.css' "$_LEDE_FILES/usr/share/ucode/luci/template/themes/argon/header.ut"
assert_grep '自动配置' "$_LEDE_FILES/usr/share/luci/menu.d/zzz-luci-mwan3-tab.json"
assert_grep 'font-size: 2.85rem' "$_LEDE_FILES/www/luci-static/argon/css/lede-brand-font.css"
assert_grep 'font-size: 30px' "$_LEDE_FILES/www/luci-static/argon/css/lede-brand-font.css"

assert_pkg_file 'commitDisableToUci' \
  package/luci-app-mwan3 -path '*/view/mwan3/network/globals.js'
assert_pkg_file 'lede-theme-page' \
  package/luci-app-mwan3 -path '*/view/mwan3/network/globals.js'
assert_pkg_file 'lede-theme-page' \
  package/luci-mod-status feeds/luci -path '*/view/status/index.js'
assert_pkg_file 'lede-theme-page' \
  package/luci-mod-status feeds/luci -path '*/view/status/wanalert-layout.js'
_ARGON_CSS=$(find package/luci-theme-argon -path '*/luci-static/argon/css/lede-brand-font.css' -type f 2>/dev/null | head -n 1 || true)
_ARGON_HDR=$(find package/luci-theme-argon -path '*/template/themes/argon/header.ut' -type f 2>/dev/null | head -n 1 || true)
[ -n "$_ARGON_CSS" ] || { echo "ERROR: lede-brand-font.css not installed in luci-theme-argon package"; exit 1; }
[ -n "$_ARGON_HDR" ] || { echo "ERROR: header.ut not installed in luci-theme-argon package"; exit 1; }
assert_grep 'DuanNingMaoBi' "$_ARGON_CSS"
assert_grep 'displayName' "$_ARGON_HDR"
echo "package OK: $_ARGON_CSS"
echo "package OK: $_ARGON_HDR"
assert_pkg_file 'lede-mwan3-setup' \
  package/mwan3 -path '*/usr/libexec/lede-mwan3-setup'
_ISPJS_PKG=$(find package/luci-app-mwan3 -path '*/view/mwan3/ispupdate.js' -type f 2>/dev/null | head -n 1 || true)
[ -n "$_ISPJS_PKG" ] || { echo "ERROR: ispupdate.js not installed in luci-app-mwan3 package"; exit 1; }
assert_grep 'luci.ispip' "$_ISPJS_PKG"
assert_grep 'syncCron' "$_ISPJS_PKG"
assert_grep 'ui.changes.apply' "$_ISPJS_PKG"
echo "package OK: $_ISPJS_PKG"
assert_grep 'luci.ispip' "$_LEDE_FILES/usr/share/rpcd/ucode/luci.isp-ip.uc"
assert_grep 'luci.ispip' "$_LEDE_FILES/usr/share/rpcd/acl.d/luci-mwan3-isp.json"
assert_grep 'sync-cron' "$_LEDE_FILES/usr/libexec/isp-ip-update"
assert_grep "option enabled '0'" "$_LEDE_FILES/etc/config/mosdns"
assert_grep '/etc/init.d/mosdns enable' "$_LEDE_FILES/etc/uci-defaults/zzz-mosdns-custom"
_MWAN3_TAB_PKG=$(find package/luci-app-mwan3 \
  -path '*/menu.d/zzz-luci-mwan3-tab.json' -type f 2>/dev/null | head -n 1 || true)
[ -n "$_MWAN3_TAB_PKG" ] || _MWAN3_TAB_PKG=$(find package/luci-app-mwan3 \
  -path '*/menu.d/luci-app-mwan3.json' -type f 2>/dev/null | head -n 1 || true)
[ -n "$_MWAN3_TAB_PKG" ] || { echo "ERROR: mwan3 menu json not found in luci-app-mwan3 package"; exit 1; }
assert_grep '自动配置' "$_MWAN3_TAB_PKG"
echo "package OK: $_MWAN3_TAB_PKG"
assert_grep 'lede-theme-page' "$_LEDE_FILES/www/luci-static/resources/lede-theme-page.js"
echo "overlay OK: lede-theme-page.js (single copy, avoids opkg clash)"
assert_grep 'paintStatus' "$_LEDE_FILES/www/luci-static/resources/view/status/autolimit.js"
assert_grep 'autolimit_status' "$_LEDE_FILES/usr/share/ucode/lede-autolimit.uc"
assert_grep 'bplus_iface_is_lan' "$_LEDE_FILES/usr/share/ucode/lede-bandix.uc"
assert_grep 'all_down_sent' "$_LEDE_FILES/usr/share/ucode/lede-watch.uc"
assert_grep '有人占用已分配地址' "$_LEDE_FILES/usr/share/ucode/lede-watch.uc"
assert_grep 'MAX_CAP_SEC' "$_LEDE_FILES/usr/libexec/packet-cap"
assert_grep 'function send_pushplus' "$_LEDE_FILES/usr/libexec/wan-alert"
assert_grep 'lede-lansec-dhcp' "$_LEDE_FILES/usr/libexec/lede-lansec"
assert_grep 'ether saddr @dhcp_ban counter drop' "$_LEDE_FILES/usr/libexec/lede-lansec"
assert_grep 'ether daddr @dhcp_ban counter drop' "$_LEDE_FILES/usr/libexec/lede-lansec"
assert_grep "cmd == 'decide'" "$_LEDE_FILES/usr/libexec/lede-lansec"
assert_grep "cmd == 'prune'" "$_LEDE_FILES/usr/libexec/lede-lansec"
assert_grep 'nat_block' "$_LEDE_FILES/usr/libexec/lede-lansec"
assert_grep 'mac_norm' "$_LEDE_FILES/usr/libexec/lede-lansec"
assert_grep 'drop_settled_pending' "$_LEDE_FILES/usr/libexec/lede-lansec"
assert_grep '/etc/lede-lansec-pending.json' "$_LEDE_FILES/usr/libexec/lede-lansec"
assert_grep 'fmtMac' "$_LEDE_FILES/www/luci-static/resources/view/network/lansec.js"
assert_grep '待确认' "$_LEDE_FILES/www/luci-static/resources/view/network/lansec.js"
assert_grep 'handleSaveApply' "$_LEDE_FILES/www/luci-static/resources/view/network/lansec.js"
assert_grep 'admin/network/lansec' "$_LEDE_FILES/usr/share/luci/menu.d/luci-lede-lansec.json"
assert_grep '/etc/init.d/lede-lansec enable' "$_LEDE_FILES/etc/uci-defaults/99-custom"
assert_grep 'mac_norm' "$_LEDE_FILES/usr/share/ucode/lede-watch.uc"
assert_grep '网关地址被冒充' "$_LEDE_FILES/usr/share/ucode/lede-watch.uc"
assert_absent 'lede-lansec-nat' "$_LEDE_FILES/usr/libexec/lede-lansec"
assert_absent 'RE_ROUTER' "$_LEDE_FILES/usr/libexec/lede-lansec"
assert_absent "ip ttl" "$_LEDE_FILES/usr/libexec/lede-lansec"
assert_grep 'batchSend' "$_LEDE_FILES/usr/libexec/wan-alert"
assert_grep 'pushplus_token' "$_LEDE_FILES/www/luci-static/resources/view/status/alertmap.js"
assert_grep "option pushplus_enabled '0'" "$_LEDE_FILES/etc/config/wanalert"
assert_grep 'seed pushplus_wechat 1' "$_LEDE_FILES/etc/uci-defaults/50-wanalert-alert-flags"
for _bad in \
  etc/init.d/lede-lan-guard \
  usr/libexec/lede-lan-guard \
  usr/libexec/lede-lan-guard-nft \
  etc/uci-defaults/60-lede-lan-guard \
  usr/share/luci/menu.d/luci-lede-lan-guard.json \
  www/luci-static/resources/view/network/languard.js
do
  [ ! -e "$_LEDE_FILES/$_bad" ] || { echo "ERROR: lan-guard leftover in overlay: $_bad"; exit 1; }
done
assert_grep 'enable_data_mount_service' "$_LEDE_FILES/usr/libexec/lede-data-setup"
assert_grep '$5=="/"' "$_LEDE_FILES/usr/libexec/lede-data-setup"
assert_grep '/sys/dev/block/' "$_LEDE_FILES/usr/libexec/lede-data-setup"
assert_grep 'find_label_part "$DISK"' "$_LEDE_FILES/usr/libexec/lede-data-setup"
assert_grep 'fix_gpt_table "$DISK"' "$_LEDE_FILES/usr/libexec/lede-data-setup"
assert_absent 'FREE_START=${FREE_START%.*}' "$_LEDE_FILES/usr/libexec/lede-data-setup"
assert_grep 'chmod +x /usr/libexec/lede-data-setup' "$_LEDE_FILES/etc/uci-defaults/10-lede-data-enable"
assert_grep 'lede_fixup_script_modes' "$_LEDE_FILES/etc/uci-defaults/99-custom"
assert_grep '/sbin/poweroff' "$_LEDE_FILES/usr/libexec/lede-poweroff"
assert_grep '/usr/libexec/lede-poweroff' "$_LEDE_FILES/usr/share/rpcd/acl.d/luci-lede-poweroff.json"
assert_grep 'handlePoweroff' "$_LEDE_FILES/www/luci-static/resources/view/system/reboot.js"
assert_absent '宽带监控' "$_LEDE_FILES/usr/share/luci/menu.d/luci-app-wan-monitor.json"
assert_grep 'xiaomi-phone' "$_LEDE_FILES/www/luci-static/resources/view/status/index.js"
assert_overlay 'www/luci-static/resources/vendor/topo-icons/client-xiaomi-phone.svg'
assert_overlay 'www/luci-static/resources/vendor/topo-icons/client-huawei-ap.svg'
assert_overlay 'www/luci-static/resources/vendor/topo-icons/client-nvr.svg'
if grep -R --include='*.json' -F '宽带监控' "$_LEDE_FILES/usr/share/luci/menu.d" >/dev/null 2>&1; then
  echo "ERROR: 宽带监控 menu leaked into LuCI overlay"
  exit 1
fi
echo "absent OK: 宽带监控 menu"
[ ! -e "$_LEDE_FILES/www/luci-static/resources/view/status/wanmonitor.js" ] || {
  echo "ERROR: unused 宽带监控 page still in overlay"
  exit 1
}
assert_grep 'autofix_hold_min' "$_LEDE_FILES/usr/libexec/wan-alert"
assert_grep 'ping -c 2' "$_LEDE_FILES/usr/share/ucode/lede-wan-probe.uc"
assert_grep "option autofix_hold_min '5'" "$_LEDE_FILES/etc/config/wanalert"

_SYSJS=$(find feeds/luci package -path '*/view/system/system.js' -type f 2>/dev/null | head -n 1 || true)
[ -n "$_SYSJS" ] || { echo "ERROR: system.js not found after luci-mod-system patch"; exit 1; }
assert_grep '标题' "$_SYSJS"

echo "LEDE overlay compile self-check passed"
