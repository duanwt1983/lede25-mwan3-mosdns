#!/bin/sh
# macOS port of diag-wan2-alerts2.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-wan2-alerts2.sh [router-ip] [password]
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
awk -F'|' '$1 >= "2026-09-17 23:44:00" && $1 <= "2026-09-17 23:46:00" {print}' "$LOG" | while IFS= read -r line; do
  echo "$line" | hexdump -C | head -1 >/dev/null 2>&1
  echo "$line"
done
echo "=== title counts 23:44-23:46 ==="
awk -F'|' '$1 >= "2026-09-17 23:44:00" && $1 <= "2026-09-17 23:46:00" {print $3}' "$LOG" | sort | uniq -c | sort -rn
echo "=== would-push severe line category ==="
awk -F'|' '$1 >= "2026-09-17 23:44:00" && $1 <= "2026-09-17 23:46:00" && $2=="严重" {print $1,$3,$4}' "$LOG"
echo "=== ding not sent ==="
awk -F'|' '$1 >= "2026-09-17 23:44:00" && $1 <= "2026-09-17 23:46:00" && $3=="钉钉未发出" {print}' "$LOG"
cat /data/logs/alert/ding-queue.json 2>/dev/null; echo
wc -c /tmp/wan-alert.last 2>/dev/null; head -c 300 /tmp/wan-alert.last 2>/dev/null; echo
END_REMOTE
)"
router_print
