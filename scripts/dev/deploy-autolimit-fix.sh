#!/bin/sh
# macOS port of deploy-autolimit-fix.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-autolimit-fix.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=60

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
for f in /usr/libexec/lede-autolimit /usr/libexec/lede-autolimit-loop /usr/libexec/rpcd/lede-autolimit; do [ -f "$f" ] && sed -i "s/\r$//" "$f"; done
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
chmod +x /usr/libexec/lede-autolimit /usr/libexec/lede-autolimit-loop /usr/libexec/rpcd/lede-autolimit /etc/init.d/lede-autolimit
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
/etc/init.d/rpcd restart; sleep 2; ubus list 2>/dev/null | grep -i autolimit || true
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
ubus call lede-autolimit status 2>&1 | head -c 500
END_REMOTE
)"
router_print
