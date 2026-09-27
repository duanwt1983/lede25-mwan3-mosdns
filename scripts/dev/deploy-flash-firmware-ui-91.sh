#!/bin/sh
# Restore LuCI「固件升级」section on router (flash.js with handleSysupgrade).
# Usage: ./scripts/dev/deploy-flash-firmware-ui-91.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"

router_open "${1:-192.168.9.1}" "${2:-password}"
router_put "$ROOT/files/www/luci-static/resources/view/system/flash.js" \
	'/www/luci-static/resources/view/system/flash.js'
router_put "$ROOT/files/usr/share/rpcd/acl.d/zzz-lede-flash-acl.json" \
	'/usr/share/rpcd/acl.d/zzz-lede-flash-acl.json'

router_sh 'grep -q "固件升级" /www/luci-static/resources/view/system/flash.js && grep -q /data/firmware.bin /www/luci-static/resources/view/system/flash.js && echo FLASH_OK || echo FLASH_MISSING'
router_print flash-check

router_sh '[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null; rm -rf /tmp/luci-*cache* 2>/dev/null; echo cache_cleared'
router_print cache

router_sh '/etc/init.d/rpcd restart 2>/dev/null; echo rpcd_restarted'
router_print rpcd

echo "Done. 重新登录 LuCI 后打开：系统 → 备份与更新 → 固件升级（镜像写入 /data/firmware.bin）"
