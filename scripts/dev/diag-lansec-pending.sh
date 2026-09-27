#!/bin/sh
# macOS port of diag-lansec-pending.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-lansec-pending.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo === pending file ===
ls -l /tmp/lede-lansec-pending.json 2>/dev/null || echo NO_PENDING_FILE
cat /tmp/lede-lansec-pending.json 2>/dev/null; echo
echo === state ===
cat /tmp/lede-lansec.state 2>/dev/null | head -c 800; echo
echo === dhcp_ban uci ===
uci show lede-lansec | grep -E "dhcp_ban|@dhcp" || true
echo === alert path ===
uci -q get lede-log.alert.path; uci -q get lede-log.alert.enabled
echo === dhcp alert lines ===
AP=$(uci -q get lede-log.alert.path)
if [ -n "$AP" ] && [ -f "$AP" ]; then
  grep -n "DHCP\|非法" "$AP" | tail -n 20
else
  echo NO_ALERT_FILE
  ls /etc/lede-log /tmp/lede-log /mnt 2>/dev/null | head
fi
echo === kernel dhcp ===
logread -l 200 2>/dev/null | grep -F "lede-lansec-dhcp" | tail -n 15 || true
echo === flags ===
uci -q get lede-lansec.main.enabled
uci -q get lede-lansec.main.dhcp_enabled
uci -q get lede-lansec.main.dhcp_log
uci -q get lede-lansec.main.dhcp_ban
echo === svc ===
pgrep -af lede-lansec || true
END_REMOTE
)"
router_print
