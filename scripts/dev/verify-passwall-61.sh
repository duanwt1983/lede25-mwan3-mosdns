#!/bin/sh
# macOS port of verify-passwall-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./verify-passwall-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
echo "=== passwall status ==="
/etc/init.d/passwall status 2>&1
echo "=== processes ==="
ps w | grep -iE 'xray|passwall|sing-box|chinadns' | grep -v grep
echo "=== geodata bind ==="
ls -la /usr/share/xray 2>&1 | head -5
mount | grep xray
echo "=== nft passwall ==="
nft list table inet passwall 2>&1 | head -10
echo "=== curl test ==="
curl -4 -sS -m 10 -o /dev/null -w "google http=%{http_code} time=%{time_total}\n" https://www.google.com 2>&1 || echo curl_failed
END_REMOTE
)"
router_print
