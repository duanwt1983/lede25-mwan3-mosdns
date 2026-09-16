#!/bin/bash
# Fail before the 2-hour compile if the image set is wrong.
set -euo pipefail

must_y=(
  CONFIG_PACKAGE_luci-nginx
  CONFIG_PACKAGE_nftables-json
  CONFIG_PACKAGE_luci-theme-argon
  CONFIG_PACKAGE_luci-app-passwall
  CONFIG_PACKAGE_luci-app-mosdns
  CONFIG_PACKAGE_mosdns
  CONFIG_PACKAGE_mosdns-mwan
  CONFIG_PACKAGE_librespeed-go
  CONFIG_PACKAGE_qosmate
  CONFIG_PACKAGE_luci-app-qosmate
  CONFIG_PACKAGE_luci-i18n-qosmate-zh-cn
  CONFIG_PACKAGE_jq
  CONFIG_PACKAGE_tc-full
  CONFIG_PACKAGE_kmod-ifb
  CONFIG_PACKAGE_bandix-plus
  CONFIG_PACKAGE_luci-app-bandix-plus
  CONFIG_PACKAGE_luci-app-samba4
  CONFIG_PACKAGE_samba4-server
  CONFIG_PACKAGE_luci-app-diskman
  CONFIG_PACKAGE_luci-i18n-diskman-zh-cn
  CONFIG_PACKAGE_parted
  CONFIG_PACKAGE_blkid
  CONFIG_PACKAGE_kmod-ixgbe
  CONFIG_PACKAGE_smartmontools
  CONFIG_PACKAGE_ip-full
  CONFIG_PACKAGE_luci-app-filemanager
  CONFIG_PACKAGE_luci-app-ddns-go
  CONFIG_PACKAGE_ddns-go
  CONFIG_PACKAGE_luci-app-ttyd
  CONFIG_PACKAGE_luci-app-mwan3
  CONFIG_PACKAGE_mwan3
  CONFIG_PACKAGE_tcpdump
  CONFIG_PACKAGE_wireshark
  CONFIG_PACKAGE_firewall4
  CONFIG_TARGET_ROOTFS_EXT4FS
  CONFIG_GRUB_EFI_IMAGES
  CONFIG_VMDK_IMAGES
)

must_n=(
  CONFIG_PACKAGE_uhttpd
  CONFIG_PACKAGE_uhttpd-mod-ubus
  CONFIG_PACKAGE_luci-ssl
  CONFIG_PACKAGE_nftables-nojson
  CONFIG_PACKAGE_firewall
  CONFIG_PACKAGE_iptables
  CONFIG_PACKAGE_iptables-nft
  CONFIG_PACKAGE_iptables-zz-legacy
  CONFIG_PACKAGE_ip6tables
  CONFIG_PACKAGE_ip6tables-nft
  CONFIG_PACKAGE_ip6tables-zz-legacy
  CONFIG_PACKAGE_ddns-scripts_aliyun
  CONFIG_PACKAGE_ddns-scripts_dnspod
  CONFIG_PACKAGE_luci-app-ddns
  CONFIG_PACKAGE_luci-app-arpbind
  CONFIG_PACKAGE_luci-app-filetransfer
  CONFIG_PACKAGE_luci-app-ssr-plus
  CONFIG_PACKAGE_luci-app-vsftpd
  CONFIG_PACKAGE_luci-app-vlmcsd
  CONFIG_PACKAGE_luci-app-autoreboot
  CONFIG_PACKAGE_luci-i18n-arpbind-zh-cn
  CONFIG_PACKAGE_luci-i18n-filetransfer-zh-cn
  CONFIG_PACKAGE_luci-app-passwall_Iptables_Transparent_Proxy
  CONFIG_PACKAGE_luci-app-istorex
  CONFIG_PACKAGE_luci-app-store
  CONFIG_PACKAGE_luci-app-quickstart
  CONFIG_PACKAGE_luci-app-fastnet
  CONFIG_PACKAGE_fastnet
  CONFIG_PACKAGE_homebox
  CONFIG_PACKAGE_luci-app-netspeedtest
  CONFIG_PACKAGE_ookla-speedtest
  CONFIG_PACKAGE_iperf3
  CONFIG_PACKAGE_iperf3-ssl
  CONFIG_PACKAGE_mdadm
  CONFIG_PACKAGE_tc-tiny
  CONFIG_TARGET_ROOTFS_SQUASHFS
  CONFIG_GRUB_IMAGES
)

fail=0

for k in "${must_y[@]}"; do
  if ! grep -q "^${k}=y$" .config; then
    echo "AUDIT FAIL: missing ${k}=y"
    grep -E "^# ${k} is not set|^${k}=" .config || true
    fail=1
  fi
done

for k in "${must_n[@]}"; do
  if grep -q "^${k}=y$" .config; then
    echo "AUDIT FAIL: ${k} must not be selected"
    fail=1
  fi
done

if ! grep -q '^CONFIG_TARGET_ROOTFS_PARTSIZE=2048$' .config; then
  echo "AUDIT FAIL: rootfs partsize is not 2048"
  grep TARGET_ROOTFS_PARTSIZE .config || true
  fail=1
fi

router_defaults=$(awk '
  /^DEFAULT_PACKAGES\.router:=/ { p=1 }
  p { print }
  p && !/\\$/ { exit }
' include/target.mk)
echo "==== DEFAULT_PACKAGES.router ===="
echo "$router_defaults"
if echo "$router_defaults" | grep -qE 'ddns-scripts_aliyun|ddns-scripts_dnspod|luci-app-ssr-plus|luci-app-arpbind|luci-app-filetransfer|\biptables\b|\bip6tables\b|\bfirewall\b'; then
  echo "AUDIT FAIL: Lean DEFAULT_PACKAGES.router still contains junk"
  fail=1
fi
if ! echo "$router_defaults" | grep -q 'luci-app-diskman'; then
  echo "AUDIT FAIL: luci-app-diskman missing from DEFAULT_PACKAGES.router"
  fail=1
fi
if ! echo "$router_defaults" | grep -q 'kmod-ixgbe'; then
  echo "AUDIT FAIL: kmod-ixgbe missing from DEFAULT_PACKAGES.router"
  fail=1
fi

echo "==== audit snapshot ===="
grep -E '^CONFIG_PACKAGE_(luci-nginx|nginx|uhttpd|luci-theme-argon|luci-app-argon-config|luci-app-mwan3|mwan3|firewall4|nftables-json|iptables|luci-app-passwall|luci-app-samba4|ddns-scripts)=' .config || true

if [ "$fail" -ne 0 ]; then
  echo "Config audit failed. Fix defaults before compiling."
  exit 1
fi

echo "Config audit passed."
