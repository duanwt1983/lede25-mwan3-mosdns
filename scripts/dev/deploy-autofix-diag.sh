#!/bin/sh
# macOS port of deploy-autofix-diag.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-autofix-diag.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=60

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
uci -q get wanalert.main.autofix_wan || echo default_on
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
/usr/libexec/lede-autofix down-Wan_2 2>&1; echo exit=$?
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
head -1 /usr/libexec/lede-autofix | od -An -tx1 | head -1
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
for f in /usr/libexec/lede-autofix; do sed -i "s/\\r$//" "$f"; done
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
/usr/libexec/lede-autofix down-Wan_2 2>&1; echo exit=$?
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
ubus call network.interface.Wan_2 status 2>&1 | grep -E "\"up\"|\"l3_device\"" | head -3
END_REMOTE
)"
router_print
