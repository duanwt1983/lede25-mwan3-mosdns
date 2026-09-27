#!/bin/sh
# macOS port of _capture-start.ps1. Talks to the router over LuCI ubus.
# Usage: ./_capture-start.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=30

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
rm -f /tmp/lg-cap-eth*.txt; for d in eth0 eth1 eth2 eth3 eth4 eth5 eth6 eth7; do [ -e /sys/class/net/$d ] || continue; (timeout 180 tcpdump -i $d -nn -e -vvv -s 400 "udp and (src port 67 or dst port 67)" > /tmp/lg-cap-$d.txt 2>&1; echo CAP_DONE >> /tmp/lg-cap-$d.txt) & done; sleep 2; echo STARTED; ps | grep "[t]cpdump"
END_REMOTE
)"
router_print
