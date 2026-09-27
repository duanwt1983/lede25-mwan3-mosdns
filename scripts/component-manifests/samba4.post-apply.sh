#!/bin/sh
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
chmod 755 /usr/libexec/lede-samba-policy /usr/libexec/lede-samba-sync \
	/etc/init.d/lede-samba-policy /etc/init.d/lede-samba-sync /etc/init.d/samba4 \
	/etc/hotplug.d/block/20-smb /etc/hotplug.d/block/21-lede-samba-policy 2>/dev/null || true
/usr/libexec/lede-samba-policy 2>/dev/null || true
/usr/libexec/lede-samba-sync 2>/dev/null || true
/etc/init.d/samba4 reload >/dev/null 2>&1 || true
rm -rf /tmp/luci-*cache* 2>/dev/null || true
[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null || true
