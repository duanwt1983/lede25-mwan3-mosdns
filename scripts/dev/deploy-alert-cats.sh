#!/bin/sh
# macOS port of deploy-alert-cats.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-alert-cats.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Deploy alert category + Mbps unit files to 192.168.8.1 via LuCI cgi-upload.

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_cgi_put "$ROOT/files/usr/share/ucode/lede-watch.uc" '/usr/share/ucode/lede-watch.uc'
router_cgi_put "$ROOT/files/usr/share/ucode/lede-log.uc" '/usr/share/ucode/lede-log.uc'
router_cgi_put "$ROOT/files/usr/libexec/wan-alert" '/usr/libexec/wan-alert'
router_cgi_put "$ROOT/files/usr/libexec/lede-lansec" '/usr/libexec/lede-lansec'
router_cgi_put "$ROOT/files/usr/libexec/lede-log-read" '/usr/libexec/lede-log-read'
router_cgi_put "$ROOT/files/www/luci-static/resources/view/status/alertmap.js" '/www/luci-static/resources/view/status/alertmap.js'
router_cgi_put "$ROOT/files/www/luci-static/resources/view/status/alertlog.js" '/www/luci-static/resources/view/status/alertlog.js'
router_cgi_put "$ROOT/files/www/luci-static/resources/view/status/loghub.js" '/www/luci-static/resources/view/status/loghub.js'
router_cgi_put "$ROOT/files/www/luci-static/resources/view/status/logcenter.js" '/www/luci-static/resources/view/status/logcenter.js'
router_cgi_put "$ROOT/files/www/luci-static/resources/view/status/ratechart.js" '/www/luci-static/resources/view/status/ratechart.js'
router_cgi_put "$ROOT/files/www/luci-static/resources/view/status/wanmonitor.js" '/www/luci-static/resources/view/status/wanmonitor.js'
router_cgi_put "$ROOT/files/www/luci-static/resources/view/status/hwinfo.js" '/www/luci-static/resources/view/status/hwinfo.js'

router_sh '/etc/init.d/wanalert restart' || true
router_print 'RESTART wanalert'
router_sh '/etc/init.d/lede-lansec restart' || true
router_print 'RESTART lede-lansec'
router_sh '/usr/sbin/wan-alert' || true
router_print WANALERT_EXEC
