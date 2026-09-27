#!/bin/sh
# macOS port of diag-wan2-alerts.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-wan2-alerts.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
LOG=/data/logs/alert/sys-alert.log
[ -f "$LOG" ] || LOG=/overlay/logs/sys-alert.log
echo "LOG=$LOG"
echo "=== Wan_2 / down / line alerts last 2h (tail 5000) ==="
tail -5000 "$LOG" 2>/dev/null | grep -iE 'Wan_2|wan_2|断线|掉线|线路|all-down|down-Wan' | tail -80
echo "=== count by level (Wan_2 related, last 5000 lines) ==="
tail -5000 "$LOG" 2>/dev/null | grep -iE 'Wan_2|wan_2' | awk -F'|' '{print $2}' | sort | uniq -c
echo "=== ding queue / state ==="
cat /tmp/wan-alert.state 2>/dev/null | head -c 800; echo
ls -la /tmp/lede-ding-queue.json /data/logs/alert/ding-queue.json 2>/dev/null
echo "=== wan-alert.state keys with Wan_2/down ==="
cat /tmp/wan-alert.state 2>/dev/null | tr ',' '\n' | grep -iE 'Wan_2|down' || true
echo "=== recent hotplug / mwan3 Wan_2 ==="
logread 2>/dev/null | grep -iE 'Wan_2|wan_2|wan-alert|mwan3' | tail -30
END_REMOTE
)"
router_print
