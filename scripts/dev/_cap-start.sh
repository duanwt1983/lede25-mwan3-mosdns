#!/bin/sh
# macOS port of _cap-start.ps1. Talks to the router over LuCI ubus.
# Usage: ./_cap-start.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=30

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
rm -f /tmp/lgcap; (timeout 25 tcpdump -i eth7 -nn -e -vvv -s 400 -c 10 "udp and (src port 67 or dst port 67)" > /tmp/lgcap 2>&1; echo CAP_DONE >> /tmp/lgcap) & echo CAP_STARTED; sleep 2; ps | grep "[t]cpdump"
END_REMOTE
)"
router_print
