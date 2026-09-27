#!/bin/sh
# macOS port of diag-wan2-count.ps1. Talks to the router over LuCI ubus.
# Usage: ./run-diag-wan2-count.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat "$HERE/diag-wan2-count.sh")"
router_print
