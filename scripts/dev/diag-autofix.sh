#!/bin/sh
# macOS port of diag-autofix.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-autofix.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo === uci autofix ===
uci show wanalert.main | grep -E 'enabled|autofix|wfix_|alert_down|dingtalk_webhook|cooldown' | sed 's/dingtalk_webhook=.*/dingtalk_webhook=SET/'
echo === bins ===
ls -la /usr/libexec/lede-autofix /usr/libexec/wan-alert
head -n 2 /usr/libexec/lede-autofix
echo === locks state ===
ls -ld /tmp/lede-autofix*.lock /tmp/wan-alert.lock 2>/dev/null || echo no_locks
cat /tmp/wan-alert.state 2>/dev/null | head -c 800; echo
echo === autofix json ===
cat /tmp/lede-autofix.json 2>/dev/null; echo
echo === last report ===
cat /tmp/lede-fix-report.json 2>/dev/null; echo
echo === ding last ===
head -c 200 /tmp/wan-alert.last 2>/dev/null; echo
echo === alert log ===
tail -n 25 /data/logs/alert/sys-alert.log 2>/dev/null || tail -n 25 /tmp/sys-alert.log 2>/dev/null
echo === procs ===
pgrep -af 'lede-autofix|wan-alert' || true
echo === ifaces ===
ubus list | grep network.interface | grep -i wan || true
END_REMOTE
)"
router_print
