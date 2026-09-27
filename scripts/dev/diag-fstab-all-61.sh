#!/bin/sh
# macOS port of diag-fstab-all-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-fstab-all-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
uci show fstab; echo ---; ls -la /etc/config/fstab /etc/fstab 2>&1; block info 2>&1
END_REMOTE
)"
router_print
