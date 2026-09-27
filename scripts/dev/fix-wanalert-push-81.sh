#!/bin/sh
# macOS port of fix-wanalert-push-81.ps1. Talks to the router over LuCI ubus.
# Usage: ./fix-wanalert-push-81.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

# Enable PushPlus WeChat on router and run alert test.

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
uci set wanalert.main.pushplus_wechat=1
uci set wanalert.main.pushplus_app=1
uci -q get wanalert.main.pushplus_enabled | grep -q 1 || uci set wanalert.main.pushplus_enabled=1
uci commit wanalert
echo wechat=$(uci -q get wanalert.main.pushplus_wechat) app=$(uci -q get wanalert.main.pushplus_app) pp=$(uci -q get wanalert.main.pushplus_enabled)
/usr/sbin/wan-alert test manual 2>&1; echo test_exit=$?
echo pp_last:
cat /tmp/wan-alert.pp.last 2>/dev/null
echo ding_last:
cat /tmp/wan-alert.last 2>/dev/null
END_REMOTE
)"
router_print
