#!/bin/sh
# macOS port of restore-services-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./restore-services-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=300

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/libexec/lede-data-mount" '/usr/libexec/lede-data-mount'

router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
echo "=== restore /data binds ==="
df -h /data | tail -1
[ -x /usr/libexec/lede-data-mount ] && /usr/libexec/lede-data-mount bind
mount | grep -E 'sda3|/data|xray|v2ray|passwall|mosdns'

echo "=== restore UCI enable (was 0 after disk maintenance) ==="
uci set mosdns.config.enabled=1
uci set passwall.@global[0].enabled=1
uci commit mosdns
uci commit passwall

echo "=== regenerate mosdns config ==="
[ -x /usr/libexec/mosdns-gen ] && /usr/libexec/mosdns-gen
[ -x /usr/libexec/mosdns-apply-luci ] && /usr/libexec/mosdns-apply-luci

echo "=== start services ==="
/etc/init.d/mosdns restart 2>&1
sleep 2
/etc/init.d/passwall restart 2>&1
sleep 4
/etc/init.d/mwan3 restart 2>&1 || true
/etc/init.d/dnsmasq restart 2>&1

echo "=== verify ==="
echo "mosdns_enabled=$(uci get mosdns.config.enabled)"
echo "passwall_enabled=$(uci get passwall.@global[0].enabled)"
ps w | grep -iE 'mosdns|passwall|sing-box|chinadns|xray' | grep -v grep
ss -lntp 2>/dev/null | grep 5335 || netstat -lntp 2>/dev/null | grep 5335
ls -la /var/etc/mosdns.yaml 2>&1 | head -1
[ -f /tmp/log/passwall.log ] && tail -5 /tmp/log/passwall.log
echo "dnsmasq=$(/etc/init.d/dnsmasq status 2>&1 | head -1)"
echo "network=$(/etc/init.d/network status 2>&1 | head -1)"
echo "nginx=$(/etc/init.d/nginx status 2>&1 | head -1)"
echo "rpcd=$(/etc/init.d/rpcd status 2>&1 | head -1)"
END_REMOTE
)"
router_print
