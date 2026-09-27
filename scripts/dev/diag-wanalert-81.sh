#!/bin/sh
# macOS port of diag-wanalert-81.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-wanalert-81.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo === wanalert uci ===
uci show wanalert.main 2>/dev/null | sort
echo === service ===
ps w 2>/dev/null | grep wan-alert | grep -v grep
/etc/init.d/wanalert status 2>&1
echo === interfaces ===
ubus call network.interface dump 2>/dev/null | jsonfilter -e '@.interface[*].interface' 2>/dev/null
ip -4 route show default 2>/dev/null
echo === log path ===
uci -q get wanalert.main.log_path
uci -q get lede-log.alert.path
ls -la /data/logs/alert/ 2>/dev/null | tail -5
ls -la /tmp/wan-alert* 2>/dev/null
echo === log tail ===
LOG=$(uci -q get wanalert.main.log_path)
[ -z "$LOG" ] && LOG=$(uci -q get lede-log.alert.path)
[ -d "$LOG" ] && LOG="$LOG/sys-alert.log"
[ -f "$LOG" ] && tail -20 "$LOG" || echo no_log_file
echo === test manual ===
/usr/sbin/wan-alert test manual 2>&1
echo === neigh ===
ip neigh show dev br-lan 2>/dev/null | head -20
END_REMOTE
)"
router_print
