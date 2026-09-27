#!/bin/sh
# Runs on router after pack extract (from build-lede-component-pack.sh when present).
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
chmod 755 /usr/libexec/lede-samba-* /etc/init.d/lede-samba-* /etc/init.d/samba4 \
	/etc/hotplug.d/block/20-smb /etc/hotplug.d/block/21-lede-samba-policy 2>/dev/null || true
/etc/init.d/lede-samba-dedupe disable 2>/dev/null || true
rm -f /usr/libexec/lede-samba-dedupe /etc/init.d/lede-samba-dedupe
/etc/init.d/lede-samba-policy enable 2>/dev/null || true
/etc/init.d/lede-samba-sync enable 2>/dev/null || true
/usr/libexec/lede-samba-policy 2>/dev/null || true
/usr/libexec/lede-samba-sync 2>/dev/null || true
