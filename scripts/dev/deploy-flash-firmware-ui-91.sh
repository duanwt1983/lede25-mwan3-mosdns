#!/bin/sh
# LuCI 固件升级：flash.js + /data 上传 + sysupgrade 辅助脚本（整盘刷机后需重新执行）
# Usage: ./scripts/dev/deploy-flash-firmware-ui-91.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=300

router_open "${1:-192.168.9.1}" "${2:-password}"

router_put "$ROOT/files/www/luci-static/resources/view/system/flash.js" \
	'/www/luci-static/resources/view/system/flash.js'
router_put "$ROOT/files/usr/share/rpcd/acl.d/zzz-lede-flash-acl.json" \
	'/usr/share/rpcd/acl.d/zzz-lede-flash-acl.json'
router_put "$ROOT/files/usr/libexec/lede-firmware-prepare.sh" \
	'/usr/libexec/lede-firmware-prepare.sh' 755
router_put "$ROOT/files/usr/libexec/lede-firmware-mark-flash.sh" \
	'/usr/libexec/lede-firmware-mark-flash.sh' 755
router_put "$ROOT/files/usr/libexec/lede-firmware-delete.sh" \
	'/usr/libexec/lede-firmware-delete.sh' 755
router_put "$ROOT/files/usr/libexec/lede-firmware-progress.sh" \
	'/usr/libexec/lede-firmware-progress.sh' 755
router_put "$ROOT/files/etc/uci-defaults/46-lede-firmware-cleanup" \
	'/etc/uci-defaults/46-lede-firmware-cleanup'
router_put "$ROOT/files/etc/uci-defaults/45-nginx-firmware-upload" \
	'/etc/uci-defaults/45-nginx-firmware-upload'
router_put "$ROOT/files/etc/init.d/lede-cgi-tmp" \
	'/etc/init.d/lede-cgi-tmp' 755
router_put "$ROOT/files/etc/nginx/conf.d/luci.locations" \
	'/etc/nginx/conf.d/luci.locations'
router_put "$ROOT/files/etc/uwsgi/vassals/luci-cgi_io.ini" \
	'/etc/uwsgi/vassals/luci-cgi_io.ini'

router_sh "$(cat <<'END_REMOTE'
/etc/uci-defaults/45-nginx-firmware-upload 2>/dev/null || true
/etc/init.d/lede-cgi-tmp enable 2>/dev/null || true
/etc/init.d/lede-cgi-tmp start 2>/dev/null || true
/etc/uci-defaults/46-lede-firmware-cleanup 2>/dev/null || true
/etc/init.d/nginx reload 2>/dev/null || /etc/init.d/nginx restart 2>/dev/null || true
/etc/init.d/uwsgi restart 2>/dev/null || true
test -x /usr/libexec/lede-firmware-prepare.sh && echo PREPARE_OK || echo PREPARE_MISSING
grep -q "不会自动刷写" /www/luci-static/resources/view/system/flash.js && \
grep -q lede-firmware-progress /www/luci-static/resources/view/system/flash.js && \
echo FLASH_OK || echo FLASH_MISSING
END_REMOTE
)"
router_print flash-check

router_sh '[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null; rm -rf /tmp/luci-*cache* 2>/dev/null; /etc/init.d/rpcd restart 2>/dev/null; echo done'
router_print post

echo "Done. Ctrl+F5 → 系统 → 备份与更新 → 刷写固件…"
