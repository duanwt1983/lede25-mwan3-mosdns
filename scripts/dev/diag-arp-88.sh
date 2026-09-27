#!/bin/sh
# macOS port of diag-arp-88.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-arp-88.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo === arp 8.88 ===
ip neigh show 192.168.8.88
cat /proc/net/arp | grep -E "192.168.8.88|60:9b:b4:b8:20:50|0c:91:60:bc:2f:da" || true
echo === leases both mac/ip ===
awk '{print $1,$2,$3,$4}' /tmp/dhcp.leases | grep -Ei "8.88|60:9b:b4:b8:20:50|0c:91:60:bc:2f:da" || true
echo === all 8.8x nearby ===
awk '{print $2,$3,$4}' /tmp/dhcp.leases | grep -E "192.168.8.8[0-9] "
echo === mac 609bb4 and 0c9160 ===
awk '{print $2,$3,$4}' /tmp/dhcp.leases | grep -Ei "60:9b:b4|0c:91:60"
echo === bridge fdb ===
bridge fdb show br br-lan 2>/dev/null | grep -Ei "60:9b:b4:b8:20:50|0c:91:60:bc:2f:da" || true
echo === dmesg conflict ===
dmesg 2>/dev/null | grep -iE "8.88|duplicate|conflict" | tail -n 20
echo === alert lines 8.88 ===
AP=$(uci -q get lede-log.alert.path)
grep -n "192.168.8.88\|60:9b:b4:b8:20:50\|0c:91:60:bc:2f:da" "$AP" 2>/dev/null | tail -n 30
echo === pending ===
cat /etc/lede-lansec-pending.json 2>/dev/null; echo
echo === dhcp lists ===
uci show lede-lansec | grep -E "dhcp_allow|dhcp_ban|mac="
echo === oui hint ===
echo 60:9b:b4
echo 0c:91:60
END_REMOTE
)"
router_print
