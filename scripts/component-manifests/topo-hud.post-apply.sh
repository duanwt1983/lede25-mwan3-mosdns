#!/bin/sh
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
chmod 755 /usr/libexec/rpcd/wanmonitor 2>/dev/null || true
rm -rf /tmp/luci-*cache* 2>/dev/null || true
[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null || true
