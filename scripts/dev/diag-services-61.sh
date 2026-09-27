#!/bin/sh
# macOS port of diag-services-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-services-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
echo "=== what I did (recent) ==="
ls -lt /usr/share/ucode/lede-diag.uc /usr/libexec/mosdns-gen /usr/libexec/mosdns-apply-luci 2>&1 | head -5
echo "=== enabled services ==="
for s in mosdns passwall mwan3 dnsmasq firewall network nginx uwsgi rpcd lede-data-mount wan-alert; do
  en=$(/etc/init.d/$s enabled 2>/dev/null; echo $?)
  st=$(/etc/init.d/$s status 2>&1 | head -1)
  echo "$s enabled_exit=$en status=$st"
done
echo "=== uci enabled ==="
uci get mosdns.config.enabled 2>&1
uci get passwall.@global[0].enabled 2>&1
echo "=== processes ==="
ps w | grep -iE 'mosdns|passwall|xray|sing-box|chinadns|mwan3|dnsmasq|haproxy|nginx|rpcd' | grep -v grep
echo "=== ports ==="
ss -lntp 2>/dev/null | grep -E '5335|53|9091|1041|1070' || netstat -lntp 2>/dev/null | grep -E '5335|53|9091'
echo "=== mounts data ==="
mount | grep -E 'sda3|/data'
df -h /data 2>&1
echo "=== mosdns yaml ==="
ls -la /var/etc/mosdns.yaml 2>&1
head -5 /var/etc/mosdns.yaml 2>&1
echo "=== mosdns start log ==="
/etc/init.d/mosdns start 2>&1
sleep 2
ps w | grep mosdns | grep -v grep
echo "=== passwall start log ==="
/etc/init.d/passwall start 2>&1
sleep 3
ps w | grep -iE 'passwall|sing-box|chinadns' | grep -v grep
tail -15 /tmp/log/passwall.log 2>/dev/null
echo "=== logread errors ==="
logread | tail -25
END_REMOTE
)"
router_print
