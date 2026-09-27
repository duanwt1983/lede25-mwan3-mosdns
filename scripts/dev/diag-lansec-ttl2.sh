#!/bin/sh
# macOS port of diag-lansec-ttl2.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-lansec-ttl2.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo === br-lan raw ttl 6s ===
timeout 6 tcpdump -i br-lan -nn -c 60 -v ip > /tmp/lede-ttl-lan.txt 2>/tmp/lede-ttl-lan.err
echo LAN_ERR
cat /tmp/lede-ttl-lan.err
echo LAN_TTL
grep -oE "ttl [0-9]+" /tmp/lede-ttl-lan.txt | sort | uniq -c | sort -nr
echo LAN_SAMPLE
grep -E "ttl " /tmp/lede-ttl-lan.txt | head -n 12
echo === wan1 raw ttl 6s ===
timeout 6 tcpdump -i pppoe-Wan_1 -nn -c 60 -v ip > /tmp/lede-ttl-wan.txt 2>/tmp/lede-ttl-wan.err
echo WAN_ERR
cat /tmp/lede-ttl-wan.err
echo WAN_TTL
grep -oE "ttl [0-9]+" /tmp/lede-ttl-wan.txt | sort | uniq -c | sort -nr
echo WAN_SAMPLE
grep -E "ttl " /tmp/lede-ttl-wan.txt | head -n 12
echo === same-host compare 8.107 8.240 8.74 ===
grep -E "192.168.8.(107|240|74|176|38)[.:]" /tmp/lede-ttl-lan.txt | head -n 15
echo === leases of logged addrs ===
awk '{print $2,$3,$4}' /tmp/dhcp.leases | grep -E "192.168.8.(140|38|74|176|107|240|120|101|117|23|57|83) "
END_REMOTE
)"
router_print
