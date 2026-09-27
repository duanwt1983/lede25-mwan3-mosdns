#!/bin/sh
# macOS port of test-wanalert-pushplus.ps1. Talks to the router over LuCI ubus.
# Usage: ./test-wanalert-pushplus.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo === flags ===
echo pushplus_enabled=$(uci -q get wanalert.main.pushplus_enabled)
echo pushplus_wechat=$(uci -q get wanalert.main.pushplus_wechat)
echo pushplus_app=$(uci -q get wanalert.main.pushplus_app)
echo ding_enabled=$(uci -q get wanalert.main.enabled)
tok=$(uci -q get wanalert.main.pushplus_token)
if [ -n "$tok" ]; then
  echo token_len=${#tok}
  echo token_ok=yes
else
  echo token_len=0
  echo token_ok=no
fi
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
/usr/sbin/wan-alert test
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
echo === last ===
if [ -f /tmp/wan-alert.pp.last ]; then
  sed -E "s/\"token\"[[:space:]]*:[[:space:]]*\"[^\"]+\"/\"token\":\"***\"/g" /tmp/wan-alert.pp.last
else
  echo no_pp_last
fi
if [ -f /tmp/wan-alert.last ]; then
  echo --- dingtalk ---
  cat /tmp/wan-alert.last
fi
END_REMOTE
)"
router_print
