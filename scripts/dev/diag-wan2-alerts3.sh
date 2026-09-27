#!/bin/sh
# macOS port of diag-wan2-alerts3.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-wan2-alerts3.sh [router-ip] [password]
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
export LANG=zh_CN.UTF-8
echo "=== Wan_2 line events 23:44:00-23:45:59 ==="
awk -F'|' '$1 >= "2026-09-17 23:44:00" && $1 <= "2026-09-17 23:45:59" && $0 ~ /Wan_2/' "$LOG"
echo "=== pushable titles (严重|中等) with Wan_2 ==="
awk -F'|' '$1 >= "2026-09-17 23:44:00" && $1 <= "2026-09-17 23:45:59" && $0 ~ /Wan_2/ && ($2=="严重" || $2=="中等") {print $1, $2, $3, $4}' "$LOG"
echo "=== counts ==="
awk -F'|' '$1 >= "2026-09-17 23:44:00" && $1 <= "2026-09-17 23:45:59" && $0 ~ /Wan_2/ && ($2=="严重" || $2=="中等") {print $3"|"$4}' "$LOG" | sort | uniq -c
END_REMOTE
)"
router_print
