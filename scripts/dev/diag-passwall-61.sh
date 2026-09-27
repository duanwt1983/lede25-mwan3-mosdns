#!/bin/sh
# macOS port of diag-passwall-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-passwall-61.sh [router-ip] [password]
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
echo "=== passwall enabled ==="
/etc/init.d/passwall enabled; echo enabled=$?
ls -la /etc/rc.d/*passwall* 2>&1
echo "=== passwall status ==="
/etc/init.d/passwall status 2>&1
echo "=== processes ==="
ps w | grep -iE 'passwall|xray|sing-box|v2ray|haproxy|dnsmasq|chinadns' | grep -v grep
echo "=== uci global ==="
uci show passwall 2>&1 | head -40
echo "=== start try ==="
/etc/init.d/passwall start 2>&1
sleep 2
/etc/init.d/passwall status 2>&1
echo "=== logread passwall ==="
logread | grep -iE 'passwall|xray|sing-box|v2ray|haproxy' | tail -40
echo "=== data mounts ==="
df -h /data /usr/share/passwall 2>&1
mount | grep -E 'passwall|/data'
echo "=== geodata ==="
ls -la /data/geodata /usr/share/xray 2>&1 | head -15
echo "=== opkg passwall ==="
opkg list-installed | grep -i passwall
END_REMOTE
)"
router_print
