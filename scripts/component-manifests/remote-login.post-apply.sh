#!/bin/sh
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
rm -rf /tmp/luci-*cache* 2>/dev/null || true
[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null || true
if [ -x /etc/init.d/wanalert ]; then
	/etc/init.d/wanalert restart >/dev/null 2>&1 || true
fi
exit 0
