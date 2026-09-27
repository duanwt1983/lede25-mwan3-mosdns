#!/bin/sh
# Restore LEDE sysupgrade hooks after full-disk flash (stock image only has umount -a do_stage2).
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

STAGE=/www/luci-static/resources/lede-firmware/do_stage2
if [ -f "$STAGE" ]; then
	cp -f "$STAGE" /lib/upgrade/do_stage2
	chmod 755 /lib/upgrade/do_stage2
fi
exit 0
