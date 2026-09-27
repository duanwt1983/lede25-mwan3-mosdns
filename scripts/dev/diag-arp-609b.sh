#!/bin/sh
# macOS port of diag-arp-609b.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-arp-609b.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo === 609bb4 now ===
ip neigh | grep -i 60:9b:b4
awk '{print $2,$3,$4}' /tmp/dhcp.leases | grep -i 60:9b:b4 || echo no_lease
echo === 8.115 ===
ip neigh show 192.168.8.115
awk '{print $1,$2,$3,$4}' /tmp/dhcp.leases | grep 192.168.8.115 || true
echo === 8.88 now ===
ip neigh show 192.168.8.88
awk '{print $1,$2,$3,$4}' /tmp/dhcp.leases | grep 192.168.8.88 || true
echo === count 609bb4 as from-mac in alerts ===
AP=$(uci -q get lede-log.alert.path)
grep -c "60:9b:b4:b8:20:50" "$AP" 2>/dev/null
echo === unique dest IPs flipped from 609bb4 ===
grep "60:9b:b4:b8:20:50" "$AP" 2>/dev/null | grep -oE "192.168.8.[0-9]+" | sort | uniq -c | sort -nr | head -n 40
echo === pending now ===
cat /etc/lede-lansec-pending.json 2>/dev/null; echo
echo === lists ===
uci show lede-lansec | grep -E "@dhcp_|@nat_|mac="
END_REMOTE
)"
router_print
