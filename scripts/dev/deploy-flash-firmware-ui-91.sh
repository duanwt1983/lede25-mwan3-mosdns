#!/bin/sh
# Full LuCI firmware upgrade stack (upload limits, /dat cgi temp, flash UX).
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
router_put "$ROOT/files/usr/libexec/lede-firmware-upload-env.sh" \
	'/usr/libexec/lede-firmware-upload-env.sh' 755
router_put "$ROOT/files/usr/libexec/lede-firmware-upload-check.sh" \
	'/usr/libexec/lede-firmware-upload-check.sh' 755
router_put "$ROOT/files/usr/libexec/lede-firmware-upload-teardown.sh" \
	'/usr/libexec/lede-firmware-upload-teardown.sh' 755
router_put "$ROOT/files/usr/libexec/lede-firmware-cgi-io.sh" \
	'/usr/libexec/lede-firmware-cgi-io.sh' 755
router_put "$ROOT/files/usr/libexec/lede-firmware-upload-sanity.sh" \
	'/usr/libexec/lede-firmware-upload-sanity.sh' 755
router_put "$ROOT/files/dat/.keep" \
	'/dat/.keep'
router_put "$ROOT/files/etc/init.d/lede-data-mount" \
	'/etc/init.d/lede-data-mount' 755
router_put "$ROOT/files/usr/libexec/lede-firmware-restore-upgrade.sh" \
	'/usr/libexec/lede-firmware-restore-upgrade.sh' 755
router_put "$ROOT/files/www/luci-static/resources/lede-firmware/do_stage2" \
	'/www/luci-static/resources/lede-firmware/do_stage2' 755
router_put "$ROOT/files/etc/uci-defaults/46-lede-firmware-cleanup" \
	'/etc/uci-defaults/46-lede-firmware-cleanup'
router_put "$ROOT/files/etc/uci-defaults/45-nginx-firmware-upload" \
	'/etc/uci-defaults/45-nginx-firmware-upload'
router_put "$ROOT/files/etc/uci-defaults/47-lede-firmware-upload-boot" \
	'/etc/uci-defaults/47-lede-firmware-upload-boot'
router_put "$ROOT/files/etc/init.d/lede-cgi-tmp" \
	'/etc/init.d/lede-cgi-tmp' 755
router_put "$ROOT/files/etc/nginx/conf.d/luci.locations" \
	'/etc/nginx/conf.d/luci.locations'
router_put "$ROOT/files/etc/uwsgi/vassals/luci-cgi_io.ini" \
	'/etc/uwsgi/vassals/luci-cgi_io.ini'
router_put "$ROOT/files/lib/upgrade/lede-flash-dd.sh" \
	'/lib/upgrade/lede-flash-dd.sh'
router_put "$ROOT/files/lib/upgrade/do_stage2" \
	'/lib/upgrade/do_stage2' 755
router_put "$ROOT/files/usr/libexec/lede-firmware-run-sysupgrade.sh" \
	'/usr/libexec/lede-firmware-run-sysupgrade.sh' 755

router_sh "$(cat <<'END_REMOTE'
/etc/uci-defaults/47-lede-firmware-upload-boot 2>/dev/null || true
/usr/libexec/lede-firmware-upload-sanity.sh boot
/usr/libexec/lede-firmware-upload-env.sh
/etc/init.d/lede-cgi-tmp disable 2>/dev/null || true
/usr/libexec/lede-firmware-upload-env.sh
/etc/init.d/uwsgi restart
sleep 2
/etc/init.d/nginx reload
/usr/libexec/lede-firmware-upload-check.sh
grep -q "不会自动刷写" /www/luci-static/resources/view/system/flash.js && echo FLASH_OK || echo FLASH_MISSING
END_REMOTE
)"
router_print stack-check

router_sh '[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null; rm -rf /tmp/luci-*cache* 2>/dev/null; /etc/init.d/rpcd restart 2>/dev/null; echo done'
router_print post

echo "Done. 大文件上传前请确认 upload-check 全部 OK；上传过程中勿重启 nginx/uwsgi。"
