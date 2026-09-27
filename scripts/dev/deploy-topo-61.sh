#!/bin/sh
# macOS port of deploy-topo-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-topo-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=300

# Deploy topology overview (index.js) to a router (default 8.1).

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/www/luci-static/resources/view/status/index.js" '/www/luci-static/resources/view/status/index.js'
router_put "$ROOT/files/www/luci-static/resources/view/status/ratechart.js" '/www/luci-static/resources/view/status/ratechart.js'
router_put "$ROOT/files/usr/share/ucode/lede-bandix.uc" '/usr/share/ucode/lede-bandix.uc'
router_put "$ROOT/files/usr/share/ucode/lede-metrics.uc" '/usr/share/ucode/lede-metrics.uc'
router_put "$ROOT/files/usr/share/ucode/lede-wan.uc" '/usr/share/ucode/lede-wan.uc'
router_put "$ROOT/files/usr/share/ucode/lede-watch.uc" '/usr/share/ucode/lede-watch.uc'
router_put "$ROOT/files/usr/libexec/rpcd/wanmonitor" '/usr/libexec/rpcd/wanmonitor'
router_sh '[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null; /etc/init.d/wanalert restart 2>/dev/null; echo topo_deploy_ok'
router_print done
