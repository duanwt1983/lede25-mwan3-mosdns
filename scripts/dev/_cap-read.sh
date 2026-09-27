#!/bin/sh
# macOS port of _cap-read.ps1. Talks to the router over LuCI ubus.
# Usage: ./_cap-read.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=30

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo ===CAP===; cat /tmp/lgcap 2>&1; echo ===CAPPS===; ps | grep "[t]cpdump"; echo ===IF===; ip -o link show master br-lan 2>&1
END_REMOTE
)"
router_print
