#!/bin/sh
# macOS port of diag-passwall-61b.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-passwall-61b.sh [router-ip] [password]
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
echo "=== init head ==="
head -30 /etc/init.d/passwall
echo "=== which xray sing-box ==="
command -v xray; command -v sing-box; command -v chinadns-ng
ls -la /usr/bin/xray /usr/sbin/xray 2>&1
echo "=== mosdns ==="
/etc/init.d/mosdns status 2>&1; /etc/init.d/mosdns enabled; echo mosdns-enabled=$?
ps w | grep mosdns | grep -v grep
echo "=== manual start verbose ==="
sh -x /etc/init.d/passwall start 2>&1 | tail -50
sleep 3
ps w | grep -iE 'xray|sing-box|passwall|chinadns' | grep -v grep
echo "=== log tail ==="
logread | tail -30
echo "=== passwall rules bind ==="
mount | grep passwall; ls -la /usr/share/passwall/rules 2>&1 | head -10
ls -la /data/passwall/rules 2>&1 | head -10
END_REMOTE
)"
router_print
