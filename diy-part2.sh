#!/bin/bash
# Lean 25 extras: PassWall + mosdns, LibreSpeed LAN, qosmate, bandix-plus, samba4, nginx, nft mwan3.

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
chmod 755 package/mosdns-mwan/files/usr/libexec/* package/mosdns-mwan/files/usr/sbin/* \
  package/mosdns-mwan/files/usr/share/mosdns/gen-config-custom \
  package/mosdns-mwan/files/etc/hotplug.d/iface/* 2>/dev/null || true
chmod 755 files/usr/libexec/lede-wan-https files/etc/init.d/lede-wan-https \
  files/etc/uci-defaults/zzz-wan-https-10443 \
  files/usr/libexec/lede-stamp-reboot files/usr/sbin/reboot files/usr/libexec/wan-alert \
  files/usr/libexec/rpcd/wanmonitor files/etc/hotplug.d/iface/99-lede-netlog \
  files/usr/libexec/lede-data-setup files/etc/init.d/lede-data files/etc/uci-defaults/zzz-lede-data-paths \
  files/etc/uci-defaults/10-lede-data-enable \
  files/etc/init.d/lede-ubus-limits files/etc/uci-defaults/10-lede-ubus-limits \
  files/usr/libexec/lede-conntrack-tune files/etc/init.d/lede-conntrack \
  files/etc/uci-defaults/10-lede-conntrack \
  files/usr/libexec/lede-hwinfo files/etc/init.d/lede-hwinfo \
  files/etc/uci-defaults/10-lede-hwinfo \
  files/usr/libexec/lede-mgmt-bind files/etc/uci-defaults/40-lede-mgmt-bind \
  files/etc/hotplug.d/iface/30-lede-mgmt-bind 2>/dev/null || true

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

# QoSmate: CAKE/HFSC line shaping on firewall4 + nftables (WAN ingress/egress).
rm -rf package/qosmate package/luci-app-qosmate
clone_once package/qosmate https://github.com/hudra0/qosmate
clone_once package/luci-app-qosmate https://github.com/hudra0/luci-app-qosmate
if [ -f package/luci-app-qosmate/Makefile ]; then
  python3 - <<'PY'
from pathlib import Path
p = Path("package/luci-app-qosmate/Makefile")
t = p.read_text(encoding="utf-8", errors="replace")
idx = t.find("include $(TOPDIR)/feeds/luci/luci.mk")
if idx < 0:
    raise SystemExit("luci-app-qosmate Makefile missing luci.mk include")
head = t[: idx + len("include $(TOPDIR)/feeds/luci/luci.mk")]
if "PKGARCH:=all" not in head:
    head = head.replace(
        "include $(TOPDIR)/feeds/luci/luci.mk",
        "LUCI_PKGARCH:=all\ninclude $(TOPDIR)/feeds/luci/luci.mk",
    )
p.write_text(head.rstrip() + "\n\n# call BuildPackage - OpenWrt buildroot signature\n", encoding="utf-8")
print("qosmate luci: use luci.mk only")
PY
fi
rm -rf feeds/luci/applications/luci-app-qosmate package/feeds/luci/luci-app-qosmate || true

# Bandix Plus: eBPF per-device traffic stats + per-MAC rate limits.
rm -rf package/openwrt-bandix-plus package/luci-app-bandix-plus
clone_once package/openwrt-bandix-plus https://github.com/timsaya/openwrt-bandix-plus
clone_once package/luci-app-bandix-plus https://github.com/timsaya/luci-app-bandix-plus
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
  fi
fi
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
        for extra in logcenter.js loghub.js alertlog.js wanmonitor.js wanalert.js alertmap.js mosdnscache.js; do
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
assert_pkg qosmate
assert_pkg luci-app-qosmate
assert_pkg bandix-plus
assert_pkg luci-app-bandix-plus
assert_pkg luci-app-diskman
assert_pkg mwan3
assert_pkg luci-app-mwan3
assert_pkg luci-app-passwall
assert_pkg luci-app-samba4
assert_pkg tcpdump
assert_pkg wireshark
assert_pkg ip-full

rm -rf feeds/luci/applications/luci-app-diskman package/feeds/luci/luci-app-diskman
if grep -q '+smartmontools' package/luci-app-diskman/Makefile; then
  echo "luci-app-diskman still hard-depends on smartmontools"
  exit 1
fi
if [ -d feeds/luci/applications/luci-app-diskman ]; then
  echo "Lean luci-app-diskman feed copy came back"
  exit 1
fi
