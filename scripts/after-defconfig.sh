#!/bin/bash
# Select the requested set, then strip Lean's default luci apps.
# Final disable must run AFTER the last defconfig, or Lean DEFAULT_PACKAGES
# (ssr-plus, vsftpd, vlmcsd, ...) come back.

set -euo pipefail

enable_pkg() {
  local p="$1"
  sed -i "/^CONFIG_PACKAGE_${p}=/d" .config
  sed -i "/^# CONFIG_PACKAGE_${p} is not set/d" .config
  echo "CONFIG_PACKAGE_${p}=y" >> .config
}

disable_pkg() {
  local p="$1"
  sed -i "/^CONFIG_PACKAGE_${p}=/d" .config
  sed -i "/^# CONFIG_PACKAGE_${p} is not set/d" .config
  echo "# CONFIG_PACKAGE_${p} is not set" >> .config
}

force_y() {
  local k="$1"
  sed -i "/^# ${k} is not set/d; /^${k}=/d" .config
  echo "${k}=y" >> .config
}

force_n() {
  local k="$1"
  sed -i "/^# ${k} is not set/d; /^${k}=/d" .config
  echo "# ${k} is not set" >> .config
}

select_wanted() {
  enable_pkg luci-nginx
  enable_pkg nginx
  enable_pkg nginx-mod-luci
  enable_pkg openssl-util
  enable_pkg libustream-openssl
  enable_pkg luci-compat
  enable_pkg ucode
  enable_pkg ucode-mod-fs
  enable_pkg ucode-mod-uci
  enable_pkg ucode-mod-ubus
  enable_pkg smartmontools
  enable_pkg dmidecode
  enable_pkg curl
  enable_pkg luci-theme-argon
  enable_pkg luci-app-argon-config
  enable_pkg luci-app-ttyd
  enable_pkg luci-i18n-ttyd-zh-cn
  enable_pkg luci-app-passwall
  enable_pkg luci-i18n-passwall-zh-cn
  force_y CONFIG_PACKAGE_luci-app-passwall_Nftables_Transparent_Proxy
  force_y CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray
  force_y CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox
  force_y CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Geoview
  force_y CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Haproxy
  force_y CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client
  force_y CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client
  force_y CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Simple_Obfs
  force_y CONFIG_PACKAGE_luci-app-passwall_INCLUDE_V2ray_Plugin
  enable_pkg luci-app-mosdns
  enable_pkg luci-i18n-mosdns-zh-cn
  enable_pkg mosdns
  enable_pkg mosdns-mwan
  enable_pkg v2dat
  enable_pkg luci-app-ddns-go
  enable_pkg ddns-go
  enable_pkg librespeed-go
  enable_pkg bandix-plus
  enable_pkg luci-app-bandix-plus
  enable_pkg luci-i18n-bandix-plus-zh-cn
  enable_pkg luci-app-samba4
  enable_pkg luci-i18n-samba4-zh-cn
  enable_pkg samba4-server
  enable_pkg wsdd2
  enable_pkg luci-app-diskman
  enable_pkg luci-i18n-diskman-zh-cn
  enable_pkg luci-app-filemanager
  enable_pkg luci-i18n-filemanager-zh-cn
  enable_pkg luci-app-mwan3
  enable_pkg luci-i18n-mwan3-zh-cn
  enable_pkg mwan3
  enable_pkg ip-full
  enable_pkg libnetfilter-conntrack
  enable_pkg parted
  enable_pkg blkid
  enable_pkg block-mount
  enable_pkg e2fsprogs
  enable_pkg kmod-fs-ext4
  enable_pkg kmod-fs-ntfs3
  enable_pkg kmod-fs-exfat
  enable_pkg kmod-usb-storage
  enable_pkg kmod-usb-storage-uas
  enable_pkg kmod-ixgbe
  enable_pkg kmod-i2c-algo-bit
  enable_pkg kmod-mdio
  enable_pkg wget-ssl
  enable_pkg tcpdump
  enable_pkg wireshark

  enable_pkg firewall4
  enable_pkg nftables-json
  disable_pkg nftables-nojson
  enable_pkg kmod-nft-core
  enable_pkg kmod-nft-nat
  enable_pkg kmod-nft-bridge
  enable_pkg kmod-nft-arp
  enable_pkg kmod-nfnetlink-log
  enable_pkg kmod-nft-socket
  enable_pkg kmod-nft-tproxy
  enable_pkg kmod-nft-offload
  enable_pkg kmod-nf-reject
  enable_pkg kmod-nf-reject6
  force_n CONFIG_PACKAGE_luci-app-passwall_Iptables_Transparent_Proxy
  force_n CONFIG_PACKAGE_dnsmasq_full_ipset
  force_n CONFIG_PACKAGE_luci-app-diskman_INCLUDE_mdadm
  force_n CONFIG_PACKAGE_luci-app-diskman_INCLUDE_smartmontools

  force_y CONFIG_TARGET_ROOTFS_EXT4FS
  force_y CONFIG_TARGET_EXT4_JOURNAL
  force_n CONFIG_TARGET_ROOTFS_SQUASHFS
  sed -i '/^CONFIG_TARGET_ROOTFS_PARTSIZE=/d' .config
  echo 'CONFIG_TARGET_ROOTFS_PARTSIZE=2048' >> .config
  force_n CONFIG_GRUB_IMAGES
  force_y CONFIG_GRUB_EFI_IMAGES
  force_y CONFIG_VMDK_IMAGES
  force_y CONFIG_CCACHE
  force_n CONFIG_TARGET_IMAGES_GZIP
}

strip_unwanted() {
  for p in \
    uhttpd uhttpd-mod-ubus luci-ssl luci-ssl-openssl luci-ssl-nginx luci-light \
    nftables-nojson \
    libustream-mbedtls \
    luci-app-daed daed luci-i18n-daed-zh-cn \
    netdata luci-app-netdata luci-i18n-netdata-zh-cn \
    iperf3 iperf3-ssl homebox \
    luci-app-netspeedtest luci-i18n-netspeedtest-zh-cn ookla-speedtest \
    luci-app-fastnet fastnet luci-i18n-fastnet-zh-cn \
    luci-app-ksmbd ksmbd-server autosamba \
    luci-app-ssr-plus \
    luci-app-nlbwmon nlbwmon \
    luci-app-wol \
    luci-app-upnp miniupnpd miniupnpd-iptables miniupnpd-nftables \
    luci-app-vlmcsd vlmcsd \
    luci-app-vsftpd vsftpd vsftpd-alt \
    luci-app-turboacc \
    luci-app-autoreboot \
    luci-app-ddns ddns-scripts_aliyun ddns-scripts_dnspod \
    luci-i18n-arpbind-zh-cn luci-i18n-filetransfer-zh-cn \
    luci-i18n-vsftpd-zh-cn luci-i18n-ssr-plus-zh-cn \
    luci-i18n-vlmcsd-zh-cn luci-i18n-upnp-zh-cn \
    luci-i18n-autoreboot-zh-cn luci-i18n-wol-zh-cn \
    luci-i18n-nlbwmon-zh-cn luci-i18n-turboacc-zh-cn \
    luci-i18n-ddns-zh-cn luci-i18n-accesscontrol-zh-cn \
    luci-app-arpbind \
    luci-app-filetransfer \
    luci-app-accesscontrol \
    luci-app-unblockmusic luci-app-unblockneteasemusic \
    luci-app-adbyby-plus adbyby \
    luci-app-zerotier \
    luci-app-openclash \
    luci-app-docker luci-app-dockerman docker dockerd \
    luci-app-qbittorrent \
    luci-app-transmission \
    luci-app-aria2 \
    luci-app-xlnetacc \
    luci-app-jd-dailybonus \
    luci-app-serverchan \
    luci-app-pushbot \
    luci-app-uugamebooster \
    luci-app-aliyundrive-webdav \
    luci-app-aliyundrive-fuse \
    luci-app-istorex luci-app-store luci-app-quickstart luci-lib-taskd \
    luci-app-istore luci-i18n-quickstart-zh-cn luci-i18n-istorex-zh-cn \
    luci-app-smartinfo luci-app-smart mdadm luci-app-mdadm \
    luci-app-raid \
    firewall \
    iptables iptables-nft iptables-zz-legacy \
    ip6tables ip6tables-nft ip6tables-zz-legacy \
    iptables-mod-conntrack-extra iptables-mod-iprange \
    iptables-mod-socket iptables-mod-tproxy iptables-mod-extra \
    iptables-mod-fullconenat \
    xtables-legacy xtables-nft \
    tc-tiny
  do
    disable_pkg "$p"
  done
}

select_wanted
make defconfig
select_wanted
make defconfig
strip_unwanted
# Re-assert wanted packages. Do not run defconfig again or Lean defaults return.
select_wanted

echo "==== selected extras ===="
grep -E '^CONFIG_PACKAGE_(luci-nginx|nginx|uhttpd|luci-app-samba4|samba4-server|luci-app-passwall|luci-app-mosdns|mosdns|librespeed-go|bandix-plus|luci-app-bandix-plus|tcpdump|wireshark|luci-app-istorex|luci-app-quickstart|luci-app-fastnet|luci-app-diskman|luci-i18n-diskman-zh-cn|luci-app-filemanager|luci-app-mwan3|mwan3|parted|blkid|kmod-ixgbe|smartmontools|mdadm|nftables-json|ip-full)=' .config || true
grep -E '^CONFIG_PACKAGE_(firewall4|nftables|iptables|iptables-nft|iptables-zz-legacy|firewall)=' .config || true
grep -E '^CONFIG_(VMDK_IMAGES|GRUB_EFI_IMAGES|TARGET_ROOTFS_PARTSIZE|TARGET_ROOTFS_EXT4FS|TARGET_IMAGES_GZIP)=' .config || true
