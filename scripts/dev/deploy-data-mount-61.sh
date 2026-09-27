#!/bin/sh
# macOS port of deploy-data-mount-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-data-mount-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/libexec/lede-data-mount" /usr/libexec/lede-data-mount
router_sh "grep -n 'mkdir -p /usr/share/xray' /usr/libexec/lede-data-mount"
router_print
