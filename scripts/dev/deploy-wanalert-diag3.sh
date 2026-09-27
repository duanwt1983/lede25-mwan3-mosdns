#!/bin/sh
# macOS port of deploy-wanalert-diag3.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-wanalert-diag3.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=60

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
uci show wanalert.main
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
ubus call wanmonitor pulse 2>&1 | head -c 500
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
ls -la /etc/hotplug.d/iface/26-wan-alert /etc/hotplug.d/net/90-lede-wan-carrier 2>&1
END_REMOTE
)"
router_print
