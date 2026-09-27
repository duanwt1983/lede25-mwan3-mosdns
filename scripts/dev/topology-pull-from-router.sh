#!/bin/sh
# Pull topology layout and the status overview page from a live router.
# Usage: ./topology-pull-from-router.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120
router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"
mkdir -p "$ROOT/tmp-topo-pull"
jq -n --arg token "$UBUS_TOKEN" \
	'{jsonrpc:"2.0",id:2,method:"call",params:[$token,"wanmonitor","layout_get",{}]}' \
	| router__post | jq '.[1]' > "$ROOT/tmp-topo-pull/layout.json"
router_sh 'cat /etc/lede-topo.json 2>/dev/null || echo {}'
router_stdout | jq '.lock = "0"' > "$ROOT/files/etc/lede-topo.default.json"
printf 'SYNC_LAYOUT %s\n' "$ROOT/files/etc/lede-topo.default.json"
router_sh 'cat /www/luci-static/resources/view/status/index.js'
router_stdout > "$ROOT/files/www/luci-static/resources/view/status/index.js"
printf 'SYNC_INDEX %s\n' "$ROOT/files/www/luci-static/resources/view/status/index.js"
printf 'SYNC_DONE\n'
