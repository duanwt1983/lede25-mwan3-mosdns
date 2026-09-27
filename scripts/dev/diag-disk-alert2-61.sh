#!/bin/sh
# macOS port of diag-disk-alert2-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-disk-alert2-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
tail -100 /data/logs/alert/sys-alert.log 2>/dev/null
echo "=== kernel disk lines ==="
logread | grep sda128 | tail -10
logread | grep F2FS | tail -5
logread | grep exFAT | tail -5
END_REMOTE
)"
router_print
